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

---

## Project Structure

The manifests are organized following Kubernetes best practices with a hybrid approach:

```
task06/
├── README.md
├── 00-namespace/              # Namespace definition
│   └── namespace.yaml
├── 01-storage/                # Persistent storage
│   ├── db-master-pvc.yaml
│   └── db-replica-pvc.yaml
├── 02-config/                 # Shared configurations
│   ├── secrets.yaml
│   ├── env-cm.yaml
│   └── ca-cm.yaml
├── 03-database/               # Database components
│   ├── master/
│   │   ├── db-master-deployment.yaml
│   │   ├── db-master-service.yaml
│   │   ├── db-master-mysql-config-cm.yaml
│   │   ├── db-master-init-cm.yaml
│   │   ├── db-master-healthcheck-cm.yaml
│   │   └── certs/
│   │       ├── db-master-crt-cm.yaml
│   │       └── db-master-key-cm.yaml
│   └── slave/
│       ├── db-slave-deployment.yaml
│       ├── db-slave-service.yaml
│       ├── db-slave-mysql-config-cm.yaml
│       ├── db-slave-init-cm.yaml
│       ├── db-slave-healthcheck-cm.yaml
│       └── certs/
│           ├── db-slave-crt-cm.yaml
│           └── db-slave-key-cm.yaml
├── 04-web/                    # Web application
│   ├── web-deployment.yaml
│   ├── web-service.yaml
│   ├── web-apache-config-cm.yaml
│   ├── web-php-cm.yaml
│   └── certs/
│       ├── web-crt-cm.yaml
│       └── web-key-cm.yaml
└── 05-monitoring/             # Monitoring stack
    ├── nagios-deployment.yaml
    ├── nagios-service.yaml
    ├── nagios-configs-cm.yaml
    └── nagios-init-cm.yaml
```

### Structure Benefits

- **Numbered prefixes** - Ensures correct deployment order
- **Component separation** - Easy to locate and manage related resources
- **Certificate grouping** - Certificates isolated in `certs/` subfolders
- **Scalability** - Easy to add new components
- **GitOps friendly** - Works well with ArgoCD, Flux, etc.

## Deployment Instructions

### Deploy All Components

Deploy in order (dependencies → applications):

```bash
# 1. Create namespace
kubectl apply -f 00-namespace/

# 2. Create storage
kubectl apply -f 01-storage/

# 3. Create shared configuration
kubectl apply -f 02-config/

# 4. Deploy database master and slave
kubectl apply -f 03-database/master/
kubectl apply -f 03-database/slave/

# 5. Deploy web application
kubectl apply -f 04-web/

# 6. Deploy monitoring
kubectl apply -f 05-monitoring/
```

### Deploy Everything at Once

```bash
# Apply all manifests recursively
kubectl apply -f . --recursive

# Or apply in correct order
for dir in 00-namespace 01-storage 02-config 03-database 04-web 05-monitoring; do
  kubectl apply -f $dir/ --recursive
done
```

### Verify Deployment

```bash
# Check all resources in the namespace
kubectl get all -n bootcamp

# Check persistent volumes
kubectl get pvc -n bootcamp

# Check configmaps and secrets
kubectl get cm,secrets -n bootcamp

# Monitor pod status
kubectl get pods -n bootcamp -w
```

### Access Services

```bash
# Get service endpoints
kubectl get svc -n bootcamp

# Access web application (if using NodePort)
kubectl get svc web -n bootcamp

# Check Nagios monitoring
kubectl get svc nagios -n bootcamp
```

### Cleanup

```bash
# Delete all resources
kubectl delete -f . --recursive

# Or delete namespace (removes everything)
kubectl delete namespace bootcamp
```