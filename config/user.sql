CREATE USER IF NOT EXISTS 'terraform'@'%' IDENTIFIED BY 'teste';

GRANT ALL PRIVILEGES ON *.* TO 'terraform'@'%' IDENTIFIED BY 'teste';
FLUSH PRIVILEGES;