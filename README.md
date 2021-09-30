to ssh into ec2: 
Enter the command below in the terminal once all the resources are done creating

ssh -i ec2_keypair.pem ec2-user@$(terraform output -raw Public_IPv4_address)


When you are inside your ec2 machine use this connection string below to connect to redshift cluster: 


psql -h sample-cluster.czjqn2vqlksv.us-east-1.redshift.amazonaws.com -U sampleuser -d samplecluster -p 5439



It will prompt for password after above step, enter this password below when prompted 


saMplepswd2021



