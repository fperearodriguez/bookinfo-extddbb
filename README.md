# bookinfo-extddbb
Service Mesh configuration for bookinfo sample application with external ratings database using an egress Gateway for routing TCP traffic - [Egress TCP blog post](https://istio.io/latest/blog/2018/egress-tcp/).

In this example, the components used are as follows:
 - [Openshift Container Platform 4.8](https://docs.openshift.com/ "Openshift's Documentation")
 - [Maistra Service Mesh 2.0.6](https://maistra.io/ "Maistra's Documentation") -- [Istio v1.6](https://istio.io/v1.6/ "Istio's Documentation")
 - [Bookinfo Sample application](https://github.com/maistra/istio/tree/maistra-2.1/samples/bookinfo "Bookinfo Sample")
 - [Mysql 8.0](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/)


I have worked in two use cases for routing TCP traffic through an Egress Gateway:
1. TCP routing
2. TLS routing


## Prerequisites
 - OCP up and running.
 - DNS zone (external hosted zone in this example). Thus, I can use an alias instead of the external service name. The idea is to abstract the applications from the external service's name using the **Service Entry** object.
 - Openshift Service Mesh installed [Openshift Service Mesh](https://docs.openshift.com/container-platform/4.8/service_mesh/v2x/ossm-about.html).
 - Egress configured in SMCP [Egress config](ossm-config/basic.yaml).


## MySQL instances
Three MySQL instances are deployed outside the Mesh in the _ddbb_ project: mysql-1, mysql-2 and mysql-3. Each mysql instance has a different rating number that will be consumed by the ratings application:
* mysql-1: Ratings point equals 1.
* mysql-2: Ratings point equals 5.
* mysql-3: Ratings point equals 3.

MySQL instances have been deployed using [BuildConfigs](https://docs.openshift.com/container-platform/4.8/cicd/builds/understanding-buildconfigs.html#builds-buildconfig_understanding-builds). A MySQL image is customized for this use case using the files located in the [examples](./examples/) folder and pushed into the OCP registry. You can see the BuildConfig template that I have used [here](./mysql-deploy/).

For this example you can use any MySQL instance.

Once the image has been created, it is time to deploy the three MySQL instances. As I said, you can use any MySQL instance but keep in mind that the scripts previously mentioned should be executed. I have used [DeploymentConfig](https://docs.openshift.com/container-platform/4.8/applications/deployments/what-deployments-are.html) for deploying each MySQL, and a [Template](https://docs.openshift.com/container-platform/4.8/openshift_images/using-templates.html) with custom values for each instance.

The [MysqlTemplate](./mysql-deploy/mysql-template.yaml) uses a _params.env_ file with custom values. Once the template has been processed, some files are created: Secret, Service, PVC and DeploymentConfig.

The command for processing the template and create the Openshift's objects is:

Create ddbb project
```
oc new-project ddbb
```

Create ImageStream
```
oc apply -f mysql-deploy/imagestream-mysql-1.yaml
oc apply -f mysql-deploy/imagestream-mysql-2.yaml
oc apply -f mysql-deploy/imagestream-mysql-3.yaml
```

Create secret with MySQL credentials used by buildconfig
```
oc create secret generic mysql-credentials-1 --from-env-file=./mysql-deploy/params.env
oc create secret generic mysql-credentials-2 --from-env-file=./mysql-deploy/params-2.env
oc create secret generic mysql-credentials-3 --from-env-file=./mysql-deploy/params-3.env
```

Update the mandatory fields in the buildconfig file and create it
```
oc apply -f mysql-deploy/buildconfig-mysql-1.yaml
oc apply -f mysql-deploy/buildconfig-mysql-2.yaml
oc apply -f mysql-deploy/buildconfig-mysql-3.yaml
```

Run buildconfig
```
oc start-build mysql-1
oc start-build mysql-2
oc start-build mysql-3
```

Now, the _mysql-1_, _mysql-2_ and _mysql-3_ images are available in the Openshift Internal Registry.

Deploy mysql-1
```Shell
oc process -f mysql-deploy/mysql-template.yaml --param-file=mysql-deploy/params.env | oc create -f -
```

Deploy mysql-2
```Shell
oc process -f mysql-deploy/mysql-template.yaml --param-file=mysql-deploy/params-2.env | oc create -f -
```

Deploy mysql-3
```Shell
oc process -f mysql-deploy/mysql-template.yaml --param-file=mysql-deploy/params-3.env | oc create -f -
```

All the MySQL instances should be running in _ddbb_ project.

## Case 1: Egress TCP using Service Entry. TCP routing from sidecar to egress and from egress to external service.
### Explanation
Ratings application consumes external MySQL databases ([Ratings config here](./examples/bookinfo/bookinfo-ratings-v2-mysql.yaml)). This application will connect to _mysql.external_ host, which will be resolved by the Service Entry object. Then, the Service Entry object will route the traffic to two different external databases with different weight 80/20 (the application does not know that it is connecting to two different databases).

### App diagram
The traffic flow is:
1. The sidecar intercept the request from the app container (ratings) to _mysql.external_.
2. The Virtual Service and Destination Rule objects route the request from the sidecar (bookinfo) to the egress Gateway (istio-system).
3. At this point, the Virtual Service and Service Entry objects resolve the endpoints and route the traffic through the egress Gateway.

<img src="./examples/bookinfo/diagram_single_app.png" alt="Bookinfo app" width=100%>

### Deploy Bookinfo application
It is time to deploy the bookinfo sample application. In this use case, only one bookinfo application is deployed in bookinfo project.

Create bookinfo project
```
oc new-project bookinfo
```
Add bookinfo project to Service Mesh
```
oc create -f ossm-config/smmr.yaml
```

Deploy bookinfo application
```
oc apply -f examples/bookinfo/bookinfo.yaml
```

Get ingress domain and replace the $EXTERNAL_DOMAIN variable in _examples/bookinfo/bookinfo-gateway.yaml_ and _examples/bookinfo/ocp-route.yaml_ files
```
oc -n openshift-ingress-operator get ingresscontrollers default -o json | jq -r '.status.domain'
```

Create Gateway, Virtual Services and Destination Rules.
```
oc apply -f examples/bookinfo/bookinfo-gateway.yaml
oc apply -f examples/bookinfo/destination-rule-all-mtls.yaml
oc apply -f examples/bookinfo/ocp-route.yaml
```

At this point, the bookinfo application is up and running, but ratings application is consuming the internal database instead of the MySQL deployed previously. The application is accessible from outside the cluster using the ingress gateway.
```
export GATEWAY_URL=$(oc get route bookinfo-bookinfo-gateway -n istio-system -o jsonpath='{.spec.host}')
curl $GATEWAY_URL/productpage -I
```

### Set external database as ratings database for bookinfo sample application
Deploy ratings application with MySQL configuration
```
oc process -f examples/bookinfo/bookinfo-ratings-v2-mysql.yaml --param-file=./examples/bookinfo/params.env | oc apply -f -
```
Route all the traffic destined to the _reviews_ service to its __v3__ version and route all the traffic destined to the _ratings_ service to _ratings v2-mysql_ that uses the MySQL databases previously deployed.
```
oc apply -f examples/bookinfo/virtual-service-ratings-mysql.yaml
```

At this moment, the bookinfo application is trying to retrieve the ratings info from the external DDBB. As you can see, the ratings service is currently unavailable. Now, it's time to create the Istio objects to route the traffic through an egress Gateway in order to reach the external DDBB.

Create Istio objects
```
for file in ossm-tcp-egress/case-1/**/*.yaml; do oc apply -f $file; done
```

Once created the Istio objects, ratings service should works and retrieve data from the external database. Since the traffic is splitted 80/20 between two different databases, the data retrieved should be different if you run some requests to the application.


### Add an additional bookinfo application
Istio's TCP traffic capabilites are more limited than HTTP. There is a topic created in Istio for using TCP Service Entries with the same port [Istio topic](https://discuss.istio.io/t/multiple-tcp-serviceentries-with-same-port/7535) and the result is not good. Istio uses only the port to identify the routing for TCP traffic if no addresses are set. So, what happens in bookinfo project if two applications are trying to connect to port 3306 and whose destination is different external databases?

I tried to solve this issue in bookinfo project using **sourceLabels** for identify where the traffic is coming from, and it works in _bookinfo_ project, but a new problem is generated in _istio-system_ project.

Using **sourceLabels** I am able to match the traffic from the different app containers, and this traffic is routed to the Egress Gateway's K8S Service located in _istio-system_, port 443 in this use case. At this point, **I need to know where the traffic is coming from and where I want to route it, and it is impossible using TCP**. For HTTP traffic it can be done using [HTTPMatchRequest](https://istio.io/v1.6/docs/reference/config/networking/virtual-service/#HTTPMatchRequest) with any field, and for HTTPS traffic it can be done using [TLSMatchAttributes](https://istio.io/v1.6/docs/reference/config/networking/virtual-service/#TLSMatchAttributes) with sniHosts, for instance.

The problem is solved setting a different port in the Egress Gateway, one port for each external database.

In summary:
+ Two bookinfo applications deployed in _bookinfo_ project. App bookinfo will use the mysql-1 and mysql-2 external databases, and the App bookinfo-custom will use the mysql-3 external database.
+ Use sourceLabels in _bookinfo_ project [Virtual Service mysql-egress](./ossm-tcp-egress/case-2/bookinfo/vs-mysql-tcp-egress_v2.yaml).
+ Add an additional port to the Egress Gateway (https-9443 port).
+ One Service Entry object per external database.

In this use case, the traffic flow is:
1. The sidecar intercept the request from the app container (ratings or ratings-custom) to _mysql.external_ or _mysql-3.external_.
2. The Virtual Service and Destination Rule objects route the request from the sidecar (bookinfo) to the egress Gateway (istio-system).
3. At this point, the Virtual Service and Service Entry objects resolve the endpoints and route the traffic through the egress Gateway.

<img src="./examples/bookinfo/custom/diagram_with_custom_app.png" alt="Bookinfo app" width=100%>

### Deploy Custom Bookinfo application
It is time to deploy the custom bookinfo application. Now, two bookinfo applications will be running in _bookinfo_ project.

Deploy custom bookinfo application
```
oc apply -f examples/bookinfo/custom/bookinfo-custom.yaml
oc apply -f examples/bookinfo/custom/bookinfo-gateway.yaml
oc apply -f examples/bookinfo/custom/ocp-route-custom.yaml
oc apply -f examples/bookinfo/custom/destination-rule-all-mtls_custom.yaml
```

Deploy ratings application with MySQL configuration
```
oc process -f examples/bookinfo/custom/bookinfo-ratings-v2-mysql_custom.yaml --param-file=./examples/bookinfo/custom/params.env | oc apply -f -
```
Route all the traffic destined to the _reviews_ service to its __v3__ version and route all the traffic destined to the _ratings_ service to _ratings v2-mysql_ that uses the MySQL databases previously deployed.
```
oc apply -f examples/bookinfo/custom/virtual-service-ratings-mysql_custom.yaml
```

At this point, the bookinfo application is up and running and set with external database, but ratings application is not able to retrieve any data from _mysql-3_ instance. 
```
export GATEWAY_URL=$(oc get route bookinfo-bookinfo-gateway-custom -n istio-system -o jsonpath='{.spec.host}')
curl $GATEWAY_URL/productpage -I
```

Now, it's time to create the Istio objects to route the traffic through an egress Gateway in order to reach the _mysql-3_ external DDBB.

Create Istio objects
```
for file in ossm-tcp-egress/case-2/**/*.yaml; do oc apply -f $file; done
```

Once created the Istio objects, ratings service should works and retrieve data from the _mysql-3_ external database. Bookinfo and bookinfo-custom applications are working properly now.


## Cleanup
### MySQL Instances
Delete MySQL DeploymentConfigs
```
oc process -f mysql-deploy/mysql-template.yaml --param-file=mysql-deploy/params.env | oc delete -f -
oc process -f mysql-deploy/mysql-template.yaml --param-file=mysql-deploy/params-2.env | oc delete -f -
oc process -f mysql-deploy/mysql-template.yaml --param-file=mysql-deploy/params-3.env | oc delete -f -
```

Delete BuildConfigs
```
oc delete -f mysql-deploy/buildconfig-mysql-1.yaml
oc delete -f mysql-deploy/buildconfig-mysql-2.yaml
oc delete -f mysql-deploy/buildconfig-mysql-3.yaml
```

Delete secrets
```
oc delete secret mysql-credentials-1
oc delete secret mysql-credentials-2
oc delete secret mysql-credentials-3
```

Delete ImageStreams
```
oc delete -f mysql-deploy/imagestream-mysql-1.yaml
oc delete -f mysql-deploy/imagestream-mysql-2.yaml
oc delete -f mysql-deploy/imagestream-mysql-3.yaml
```

Delete OCP project
```
oc delete project ddbb
```
### Bookinfo
#### Bookinfo

Delete Istio objects
```
for file in ossm-tcp-egress/case-1/**/*.yaml; do oc delete -f $file; done
```

Delete ratings-v2 app
```
oc process -f examples/bookinfo/bookinfo-ratings-v2-mysql.yaml --param-file=./examples/bookinfo/params.env | oc delete -f -
```
Delete ratings and reviews routing
```
oc delete -f examples/bookinfo/virtual-service-ratings-mysql.yaml
```

Delete Routing objects
```
oc delete -f examples/bookinfo/bookinfo-gateway.yaml
oc delete -f examples/bookinfo/destination-rule-all-mtls.yaml
oc delete -f examples/bookinfo/ocp-route.yaml
```

Delete Bookinfo app
```
oc delete -f examples/bookinfo/bookinfo.yaml
```

#### Bookinfo-custom

Delete Istio objects
```
for file in ossm-tcp-egress/case-2/**/*.yaml; do oc delete -f $file; done
```

Delete custom bookinfo application
```
oc delete -f examples/bookinfo/custom/bookinfo-custom.yaml
oc delete -f examples/bookinfo/custom/bookinfo-gateway.yaml
oc delete -f examples/bookinfo/custom/ocp-route-custom.yaml
oc delete -f examples/bookinfo/custom/destination-rule-all-mtls_custom.yaml
```

Delete ratings application with MySQL configuration
```
oc process -f examples/bookinfo/custom/bookinfo-ratings-v2-mysql_custom.yaml --param-file=./examples/bookinfo/custom/params.env | oc delete -f -
```

Delete ratings and reviews routing
```
oc delete -f examples/bookinfo/custom/virtual-service-ratings-mysql_custom.yaml
```

Remove bookinfo from project from Service Mesh Members
```
oc delete -f ossm-config/smmr.yaml
```

Delete OCP project
```
oc delete project bookinfo
```


## Case 2: Egress TCP/TLS using Service Entry. TLS routing from sidecar to egress and TCP routing from egress to external service.
TO DO