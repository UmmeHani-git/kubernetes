# Kubernetes Autoscaling Setup Guide (HPA + Cluster Autoscaler on Amazon EKS)

## Overview

This guide explains how to configure **Horizontal Pod Autoscaler (HPA)** and **Cluster Autoscaler** in Kubernetes.

Autoscaling happens at two levels:

- **Pod Level Scaling (HPA)** → Automatically adds/removes application pods based on CPU usage.
- **Node Level Scaling (Cluster Autoscaler)** → Automatically adds/removes worker nodes when the cluster needs more capacity.

---

# 1. Horizontal Pod Autoscaler (HPA)

## What is HPA?

**Horizontal Pod Autoscaler (HPA)** automatically increases or decreases the number of pods in your application based on load.

**Horizontal** means scaling by **adding/removing pods**, not by increasing pod size.

---

## Example

Your application normally runs with **1 pod**.

### When traffic increases:

```text
1 pod → 2 pods → 4 pods → 8 pods
```

### When traffic decreases:

```text
8 pods → 4 pods → 2 pods → 1 pod
```

---

## How HPA Works

```text
User traffic increases
        ↓
Pods use more CPU
        ↓
Metrics Server reports CPU
        ↓
HPA detects threshold exceeded
        ↓
HPA updates Deployment replicas
        ↓
New pods are created
```

---

## HPA Architecture

```text
Users
  ↓
LoadBalancer / Service
  ↓
Pods (Deployment)
  ↑
HPA watches CPU
  ↑
Metrics Server collects pod metrics
```

---

# Steps to Deploy HPA (Metrics Server Setup)

## Step 1: Install Metrics Server

Metrics Server collects CPU and memory usage from pods and nodes.

Run:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## Step 2: Edit Metrics Server Deployment

This step is important for many Kubernetes clusters such as:

- Amazon EKS
- kubeadm clusters
- Self-managed Kubernetes clusters

Run:

```bash
kubectl edit deployment metrics-server -n kube-system
```

Find the container args section and add these two lines:

```yaml
- --kubelet-insecure-tls
- --kubelet-preferred-address-types=InternalIP
```

Final configuration should look like:

```yaml
spec:
  containers:
  - args:
    - --cert-dir=/tmp
    - --secure-port=10250
    - --kubelet-insecure-tls
    - --kubelet-preferred-address-types=InternalIP
```

Save and exit.

---

## Step 3: Wait for Metrics Server to Become Ready

Check the pod status:

```bash
kubectl get pods -n kube-system
```

Expected output:

```text
metrics-server-xxxx   1/1   Running
```

---

## Step 4: Test Metrics Collection

Verify node metrics:

```bash
kubectl top nodes
```

Verify pod metrics:

```bash
kubectl top pods
```

If metrics appear, Metrics Server is working correctly.

---

## Step 5: Verify HPA

Check Horizontal Pod Autoscaler status:

```bash
kubectl get hpa
```

Example output:

```text
NAME      REFERENCE           TARGETS   MINPODS   MAXPODS   REPLICAS
my-hpa    Deployment/myapp    45%/50%   1         10        2
```

---

# 🚀 Cluster Autoscaler Setup on Amazon EKS

This guide walks you through installing and configuring the **Cluster Autoscaler** on an Amazon EKS cluster using the AWS cloud provider.

---

## 1️⃣ Deploy Cluster Autoscaler

Apply the official Cluster Autoscaler manifest for your Kubernetes version (adjust `1.29.0` if needed):

```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/cluster-autoscaler-1.29.0/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
2️⃣ Verify the Pod
Check that the autoscaler pod is running in the kube-system namespace:


kubectl -n kube-system get pods -l app=cluster-autoscaler
Expected output:


NAME                                  READY   STATUS    RESTARTS   AGE
cluster-autoscaler-6889f6cf54-7pcsh   1/1     Running   0          2m
3️⃣ Edit Deployment (Add Cluster Name)
Edit the deployment to configure your cluster name:


kubectl -n kube-system edit deployment.apps/cluster-autoscaler
Inside the manifest, find the container args section and update:

yaml
Copy code
containers:
  - name: cluster-autoscaler
    - command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/naresh ###chnage the cluster name in place of naresh my cluster name is naresh
        image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.26.2
        imagePullPolicy: Always
        name: cluster-autoscaler
Save & exit.

4️⃣ Configure IAM Permissions
Cluster Autoscaler requires IAM permissions to scale nodes.
Go to your EKS Node Group IAM Role and attach the following policy.

👉 Either attach AmazonEKSClusterAutoscalerPolicy (AWS Managed)
or create a custom IAM policy with the JSON below.

Example IAM Policy JSON


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
Attach this to your Node Group Role.

5️⃣ Update Node Group Scaling Config
Set your min/max/desired node counts for the autoscaler:

aws eks update-nodegroup-config \
  --cluster-name naresh \
  --nodegroup-name ng-af5ac006 \
  --scaling-config minSize=2,maxSize=6,desiredSize=3
6️⃣ Check Autoscaler Logs
Watch the logs to confirm the autoscaler is working:


kubectl -n kube-system logs -f deployment/cluster-autoscaler
Look for lines like:


I0828 17:36:38.403432       1 scale_up.go:422] Pod default/nginx-deployment-12345 is unschedulable ...
I0828 17:36:38.403451       1 scale_up.go:423] Scale-up triggered ...
✅ Validation
Deploy a test workload with more pods than your current node capacity:


kubectl create deployment nginx --image=nginx --replicas=50
Check if new nodes are being added:


kubectl get nodes -w
Scale down pods and watch nodes reduce (if below maxSize and above minSize):


kubectl scale deployment nginx --replicas=1
📝 Notes
minSize ensures at least 2 nodes are always running.

maxSize sets the upper scaling limit.

desiredSize is the starting point but will be adjusted dynamically.

Ensure your Node Group IAM Role has autoscaling permissions, otherwise the pod will stay in Pending or fail to scale.

Only one Cluster Autoscaler pod should be running per cluster (it uses leader election).
