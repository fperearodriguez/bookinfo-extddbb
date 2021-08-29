CREATE TABLE `ratings` (
  `ReviewID` INT NOT NULL,
  `Rating` INT,
  PRIMARY KEY (`ReviewID`)
);
INSERT INTO ratings (ReviewID, Rating) VALUES (1, 1);
INSERT INTO ratings (ReviewID, Rating) VALUES (2, 1);