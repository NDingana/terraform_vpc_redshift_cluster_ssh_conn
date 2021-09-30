
provider "aws" {
  region = "us-east-1"
}

variable "general_tag" {
  type        = string
  default     = "TF_redshift_SSH"
  description = "The tag that will be appended to other tags"
}

#############################################################################################################
############################################# aws_vpc #######################################################
#############################################################################################################

resource "aws_vpc" "mainvpc" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true

  tags = {
    Name = "${var.general_tag}-mainvpc"
  }

}

#############################################################################################################
############################################# public_subnets ################################################
#############################################################################################################

############################################# public_subnet_1 ################################################
# Frist Public subnet with name tag public_subnet_1a in us-east-1a AZ
resource "aws_subnet" "public_subnet_1" {
  cidr_block              = "10.0.2.0/24"
  vpc_id                  = aws_vpc.mainvpc.id
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.general_tag}-public_subnet_1a"
  }

  depends_on = [aws_vpc.mainvpc]
}

############################################# public_subnet_2 ################################################
# second Public subnet with name tag public_subnet_2b in us-east-1b AZ
resource "aws_subnet" "public_subnet_2" {
  cidr_block              = "10.0.4.0/24"
  vpc_id                  = aws_vpc.mainvpc.id
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.general_tag}-public_subnet_2b"
  }
  depends_on = [aws_vpc.mainvpc]
}

############################################# public_subnet_3 ################################################
# Third Public subnet with name tag public_subnet_3c in us-east-1c AZ
resource "aws_subnet" "public_subnet_3" {
  cidr_block              = "10.0.8.0/24"
  vpc_id                  = aws_vpc.mainvpc.id
  availability_zone       = "us-east-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.general_tag}-public_subnet_3c"
  }
  depends_on = [aws_vpc.mainvpc]
}

#############################################################################################################
############################################# IGW_TF ########################################################
#############################################################################################################
resource "aws_internet_gateway" "IGW_TF" {
  vpc_id = aws_vpc.mainvpc.id

  tags = {
    Name = "${var.general_tag}-IGW"
  }
  depends_on = [aws_vpc.mainvpc]
}

#############################################################################################################
############################### one public aws_route_table ##################################################
#############################################################################################################

######################################### public-route-table ################################################
#  All three public subnets will share a single route table, 


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.mainvpc.id

  # we create a route in the public_route_table to the aws_internet_gateway
  # by doing this, all our three subnets that will be associated with this rout table will be public.
  # THerefore,ec2 instances in the public subnet can reach the internet for inbound and outbound connections

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW_TF.id
  }
  tags = {
    Name = "${var.general_tag}-public_route_table"
  }

  depends_on = [aws_vpc.mainvpc, aws_internet_gateway.IGW_TF]
}

/*
On VPC creation, the AWS API always creates an initial Main Route Table. 
This resource records the ID of that Route Table under original_route_table_id. 
The "Delete" action for a main_route_table_association consists of 
resetting this original table as the Main Route Table for the VPC. 
*/

resource "aws_main_route_table_association" "main_RT_Association" {
  vpc_id         = aws_vpc.mainvpc.id
  route_table_id = aws_route_table.public_route_table.id
  depends_on     = [aws_vpc.mainvpc, aws_route_table.public_route_table]
}
#############################################################################################################
############################## Three public-route-association ###############################################
#############################################################################################################

# All three public subnets will share a single public route table, 
# so here we associate all three public subnets to the public_route_table created above

resource "aws_route_table_association" "public_subnet_1_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_1.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_2.id
}

resource "aws_route_table_association" "public_subnet_3_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet_3.id
}


#############################################################################################################
####################################### redshift_role #######################################################
#############################################################################################################

# Let’s create a role now that we want to attach to our redshift databases:
# You create a aws_iam_role and assign the role to an redshift databases at boot time
resource "aws_iam_role" "iam_redshift_role" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "redshift.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    tag-key = "redshift-role"
    Name    = "${var.general_tag}-s3_ReadOnly"
  }


}

# Now we need to add some permissions using a policy document:
# we are using an aws managed policy here called AmazonS3ReadOnlyAccess
# by default it will allow reads only on all s3 objects by all aws resources
# json can be viewed at link below for details
# https://gist.github.com/bernadinm/6f68bfdd015b3f3e0a17b2f00c9ea3f8
resource "aws_iam_role_policy_attachment" "s3_ReadOnly_access_policy" {
  role       = aws_iam_role.iam_redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}


# aws_iam_instance_profile is what we will use to attach it to our ec2 instance.
# Any instance that will use this s3_readOnly_instance_profile 
# will have the access to read all s3 objects
resource "aws_iam_instance_profile" "s3_readOnly_instance_profile" {
  name = "s3_readOnly_instance_profile"
  role = aws_iam_role.iam_redshift_role.name
}

#############################################################################################################
#################################### create_key_pair ########################################################
#############################################################################################################

# Helper funtion to automate the key pair creation and permission of the key pair file on my local machine
# Make sure a file called ec2_keypair.pem already exist in the current directory even if its empty
resource "null_resource" "create_key_pair" {

  provisioner "local-exec" {

    command = <<-EOT
      rm -rf ec2_keypair.pem
      aws ec2 delete-key-pair --key-name ec2_keypair
      aws ec2 create-key-pair --key-name ec2_keypair --query 'KeyMaterial' --output text >ec2_keypair.pem
      chmod 400 ec2_keypair.pem
    EOT

  }

}


#############################################################################################################
############################## ec2_security_group ####################################################
#############################################################################################################

resource "aws_security_group" "ec2_security_group" {

  description = "ec2_security_group"
  vpc_id      = aws_vpc.mainvpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    /* If this needs to be specific IP of the ec2 then I will have to use and elastic IP which 
    can be known before this security group and the ec2 are created  */
     cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # egress: "By default, security groups allow all outbound traffic.""
  # https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html

  tags = {
    Name = "${var.general_tag}-ec2_security_group"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_vpc.mainvpc]
}

#############################################################################################################
############################## ec2_to_test_redshift_connection ##############################################
#############################################################################################################
# terraform apply -target="aws_instance.ec2_to_test_redshift_connection"
resource "aws_instance" "ec2_to_test_redshift_connection" {

  ami                         = "ami-087c17d1fe0178315"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_1.id
  associate_public_ip_address = true
  key_name                    = "ec2_keypair"
  vpc_security_group_ids      = [aws_security_group.ec2_security_group.id]

  tags = {
    Name = "${var.general_tag}-ec2_to_test_redshift_connection"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_subnet.public_subnet_1, 
  null_resource.create_key_pair]
}
#############################################################################################################
############################## redshift_security_group ####################################################
#############################################################################################################

resource "aws_security_group" "redshift_security_group" {

  description = "redshift_security_group"
  vpc_id      = aws_vpc.mainvpc.id

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.ec2_to_test_redshift_connection.public_ip}/32"]
  }

  # egress: "By default, security groups allow all outbound traffic.""
  # https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html

  tags = {
    Name = "${var.general_tag}-redshift_security_group"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_vpc.mainvpc, aws_instance.ec2_to_test_redshift_connection]
}
#############################################################################################################
############################## aws_redshift_subnet_group ####################################################
#############################################################################################################
resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name = "redshift-subnet-group"
  subnet_ids = [aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id,
  aws_subnet.public_subnet_3.id]
  tags = {
    Name = "${var.general_tag}-redshift_subnet_group"
  }

}

/* 
#############################################################################################################
############################## aws_redshift_cluster ####################################################
#############################################################################################################
resource "aws_redshift_cluster" "default" {
  cluster_identifier        = "sample-cluster"
  database_name             = "samplecluster"
  master_username           = "sampleuser"
  master_password           = "saMplepswd2021"
  node_type                 = "dc2.large"
  cluster_type              = "single-node"
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.id
  skip_final_snapshot       = true
  iam_roles                 = [aws_iam_role.iam_redshift_role.arn]

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_vpc.mainvpc,
    aws_security_group.redshift_security_group,
    aws_redshift_subnet_group.redshift_subnet_group,
    aws_iam_role.iam_redshift_role
  ]
} */

# attach and EIP to my ec2 instance created here
resource "aws_eip" "myeip20" {
  instance = aws_instance.ec2_to_test_redshift_connection.id
}

#############################################################################################################
################## ec2-ssh-connection to test aws_redshift_cluster ###############################################
#############################################################################################################

# terraform apply -target="null_resource.ec2_ssh_connection"

# The null_resource resource implements the standard resource lifecycle but takes no further action.
# Because provisioner has to be inside a resource, we use this null_resource to make it easy
# I could have put this provisioners inside the ec2 resource but that would have not been clear
resource "null_resource" "ec2_ssh_connection" {

  # All information needed to use ssh for the ec2
  # we need this because we need to be inside the ec2 instance to run the provisioner commands
  # As long as the connection object is incapsulated within the same resource as the provisioners,
  # the provisioners will have access to this information to connect to the ec2
  connection {
    host        = aws_eip.myeip20.public_ip
    type        = "ssh"
    port        = 22
    user        = "ec2-user"
    private_key = file("ec2_keypair.pem")
    timeout     = "1m"
    agent       = false
  }


  # The remote-exec provisioner invokes a script or command on a remote resource after it is created. 
  /*  */
  provisioner "remote-exec" {
    inline = [
       "yes Y | sudo amazon-linux-extras install postgresql10",
    ]
  }

  //aws_redshift_cluster.default

   depends_on = [aws_instance.ec2_to_test_redshift_connection,
                null_resource.create_key_pair ]
}


#############################################################################################################
############################## output #######################################################################
#############################################################################################################

output "Public_IPv4_address" {
  description = " Public IP of the instance"
  value       = aws_instance.ec2_to_test_redshift_connection.public_ip
}

/*
# Connect to your instance via SSH by piping 
# the output Public_IPv4_address to the terraform console command.
Enter the command below in the terminal once all the resources are done creating

ssh -i ec2_keypair.pem ec2-user@$(terraform output -raw Public_IPv4_address)


*/