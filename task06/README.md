# Task 06:  Migrate Docker Infrastructure to Kubernetes

## Conditions
You have the following Docker containers:

  - web — web application
  - db-master — primary database
  - db-slave — replica
  - nagios — monitoring tool

## Objective

  - Deploy all components in Kubernetes
  - Configure replication between master and slave
  - Ensure internal communication between all services
  - Expose the web app using NodePort or Ingress
  - Configure Nagios to monitor all services

### Constraints

Use the following resources:
  - Deployment for web and nagios
  - StatefulSet for db-master and db-slave
  - PersistentVolumeClaim for database storage

## Deliverable
A complete set of .yaml files for deployment