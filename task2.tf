provider "aws"{
region="ap-south-1"
profile="Naman"
access_key="*********"
secret_key="*********"
}
#SecurityGroupCreation
resource "aws_security_group" "task_sg" {
  name        = "task_sg"
  description = "Allows ssh,http and nfs connections"
  vpc_id      = "vpc-f9073d91"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
}
ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
}
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task_sg"
  }
}

#S3BucketCreation
resource "aws_s3_bucket" "my-bucket" {
  bucket = "naman-task-bucket"
  acl    = "public-read"
}

locals {
  s3_origin_id = "aws_s3_bucket.my-bucket.id"
  depends_on = [aws_s3_bucket.my-bucket, ]
}

#PuttingObjectInBucket
resource "aws_s3_bucket_object" "object" {
  bucket = "naman-task-bucket"
  key    = "taskimage.jpg"
  source = "C:/Users/KIIT/Downloads/taskimage.jpg"
  depends_on = [aws_s3_bucket.my-bucket, ]
  acl = "public-read"
}

#CreatingEC2Instance
resource "aws_instance" "task_ec2" {
  depends_on = [aws_security_group.task_sg, ]
  ami      = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "key1"
  security_groups = ["task_sg"] 
  tags = {
    Name = "task-ec2"
  }
 
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/KIIT/Downloads/key1.pem")
    host     = aws_instance.task_ec2.public_ip
  }


provisioner "remote-exec"  {
    inline = [
      "sudo yum install httpd php git amazon-efs-utils nfs-utils -y",                 
      "sudo systemctl start httpd",                  
      "sudo systemctl enable httpd",                   
      
    ]
 
 }
}

 #CreatingEFS

 resource "aws_efs_file_system" "task_nfs" {
   depends_on = [aws_security_group.task_sg, aws_instance.task_ec2, ]
  creation_token = "task2_nfs_naman"

  tags = {
    Name = "task_nfs"
  }
}

#MountingEFS
resource "aws_efs_mount_target" "mount_target" {
  depends_on = [aws_efs_file_system.task_nfs, ]
  file_system_id = aws_efs_file_system.task_nfs.id
  subnet_id      = aws_instance.task_ec2.subnet_id                         
  security_groups = ["${aws_security_group.task_sg.id}"]
}

#CopyingFromGitRepository
resource "null_resource" "null-1"  {
 depends_on = [ 
               aws_efs_mount_target.mount_target,
                  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/KIIT/Downloads/key1.pem")
    host     = aws_instance.task_ec2.public_ip
  }
  provisioner "remote-exec" {
      inline = [
        "sudo chmod ugo+rw /etc/fstab",
        "sudo echo ${aws_efs_file_system.task_nfs.dns_name}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
        "sudo mount ${aws_efs_file_system.task_nfs.dns_name}:/ /var/www/html",
        "sudo rm -rf /var/www/html/*",
        "sudo git clone https://github.com/********/taskpage.git" ,
	      "sudo cd /var/www/html/",                                 
        "sudo mv index.html /var/www/html/",                  
      ]
  }
}

  #CreatingCloudFrontDistribution

  resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.my-bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

  }

  enabled             = true
  is_ipv6_enabled     = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

#LinkingCloudFrontURLwithHTMLfile
resource "null_resource" "null-2" {
  depends_on = [aws_cloudfront_distribution.s3_distribution,]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/KIIT/Downloads/key1.pem")
    host     = aws_instance.task_ec2.public_ip
   }
   provisioner "remote-exec" {
      inline = [
      "sudo su << EOF",
      "echo \"<img src='https://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key }' >\" >> /var/www/html/index.html",
       "EOF",
       "sudo systemctl restart httpd",
   ]
 }
}