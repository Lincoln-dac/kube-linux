mysql>  create user 'admin'@'127.0.0.1' identified by 'admin'; 
Query OK, 0 rows affected (0.01 sec)

mysql>  grant all privileges on *.* to 'admin'@'127.0.0.1' with grant option;
