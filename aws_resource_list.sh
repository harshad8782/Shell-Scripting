#!/bin/bash

# Author: Santhoshkumar
# Version: v1.0.0

# Script to automate the process of listing all the resources in an AWS account
# This Script only works in AWS CLI installed and configured machines.
#
# Below are the services that are supported by this script:
# 1. EC2
# 2. RDS
# 3. S3
# 4. CloudFront
# 5. VPC
# 6. IAM
# 7. Route53
# 8. CloudWatch
# 9. CloudFormation 
# 10. Lambda
# 11. SNS
# 12. SQS
# 13. DunamoDB
# 14. VPC
# 15. EBS
#
# The script will prompt the user to enter the AWS region and the service for which the resource need to be lsited.
#
# Usage: ./aws_resource_list.sh <aws_region> <aws_service>
# Example: ./aws_resource_list.sh us-east-1 ec2

if [ $# -ne 2 ]; then
	echo "Usage: ./aws_resource_list.sh <aws_region> <aws_service>"
	echo "Example: ./aws_resource_list.sh us-east-1 ec2"
	exit 1
fi

# Assign the arguments to variables and convert the service to lowercase
aws_region=${1,,}
aws_service=${2,,}

# Check if the AWS CLI is installed
if ! command -v aws &> /dev/null; then 
	echo "AWS CLI is not installed. Please install the AWS CLI and try again."
	exit 1
fi

# Check if the AWS CLI is configured;
if [ ! -d ~/.aws ]; then;
	echo "AWS CLI is not configured. Please configure the AWS CLI and try again."
	exit 1
fi

# List the resources based on the service
case $case_service in
	ec2)
		echo "Listing EC@ Instances in $aws_region"
		aws ec2 describe-instances --region $aws_region
		;;
	rds)
		echo "Listing RDS Instances in $aws_region"
		aws rds describe-db-instances --region $aws_region
		;;
	s3)
		echo "Listing S# Buckets in $aws_region"
		aws s3api list-buckets --region $aws_region
		;;
	cloudfront)
		echo "Listing CloudFront Distributions in $aws_region"
		aws cloudfront list-distribution --region $aws_region
		;;
	vpc)
		echo "Listing VPCs in $aws_region"
		aws ec2 describe-vpcs --region $aws_region
		;;
	iam)
		echo "Listing IAM Users in $aws_region"
		aws iam list-users --region $aws_region
		;;
	route53)
		echo "Listing Route53 Hosted Zones in $aws_region"
		aws route53 list-hosted-zones --region $aws_region
		;;
	cloudwatch)
		echo "Listing CloudWatch Alarms in $aws_region"
		aws coudwatch describe-alarms --region $aws_region
		;;
	cloudformation)
		echo "Listing CloudFormation Stacks in $aws_region"
		aws cloudformation describe-stacks --region $aws_region
		;;
	lambda)
		echo "Listing Lambda Functions in $aws_region"
		aws lambda list-functions --region $aws_region
		;;
	sns)
		echo "Listing SNS Topics in $aws_region"
		aws sns list-queues --region $aws_region
		;;
	sqs)
		echo "Listing SQS Queues in $aws_region"
		aws sqss list-queues --region $aws_region
		;;
	dynamodb)
		echo "Listing DynamoDB Tables in $aws_region"
		aws dynamo list-tables --region $aws_region
		;;
	ebs)
		echo "Listing EBS Volumes in $aws_region"
		aws ec2 describe-volumes --region $aws_region
		;;
	*)
		echo "Invalid service. Please enter a valid service."
		exit 1
		;;
esac
