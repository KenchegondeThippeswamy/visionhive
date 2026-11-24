# Phase 11: KEDA Autoscaling and Karpenter Architecture

## 1. Overview

Phase 11 introduces event-driven autoscaling for VisionHive.

Local implementation:
- Minikube
- KEDA
- LocalStack SQS
- Helm
- Argo CD
- Kubernetes resource requests and limits

Karpenter is documented as a future AWS EKS implementation. It has not been deployed because AWS Organizations SCP restrictions block EKS cluster creation.

## 2. Local Architecture

Video Upload
    |
    v
API Gateway
    |
    v
LocalStack S3
    |
    v
LocalStack SQS
    |
    v
KEDA SQS Scaler
    |
    v
Ingest Worker Deployment
    |
    v
PostgreSQL

KEDA monitors the SQS queue and adjusts the number of ingest-worker pods.

## 3. KEDA Installation

Installed KEDA using Helm chart version 2.21.1.

- Helm release: keda
- Namespace: keda
- Chart version: 2.21.1

Verification:

    helm list -n keda
    kubectl get pods -n keda
    kubectl get crds | grep keda.sh

## 4. SQS Worker Autoscaling

The VisionHive Helm chart contains a KEDA ScaledObject named:

    ingest-worker-sqs

Configuration:

| Setting | Value |
|---|---|
| Target Deployment | ingest-worker |
| Trigger | AWS SQS scaler |
| Local queue | LocalStack SQS |
| Minimum replicas | 0 |
| Maximum replicas | 5 |
| Polling interval | 5 seconds |
| Cooldown period | 60 seconds |
| Queue length target | 5 |
| Authentication | aws-local-credentials |

The LocalStack endpoint is configured in:

    helm/visionhive/values-minikube.yaml

KEDA uses the existing Kubernetes Secret through TriggerAuthentication. Credentials must not be committed to Git.

## 5. Argo CD Integration

KEDA configuration is maintained in Git and deployed through the VisionHive Helm chart.

Argo CD ignores changes to:

    /spec/replicas

for the ingest-worker Deployment because KEDA controls this value.

The configuration uses:

- ignoreDifferences
- RespectIgnoreDifferences=true
- Existing pruning-disabled adoption configuration

Verification:

    kubectl get applications -n argocd
    kubectl get scaledobjects -n visionhive
    kubectl get triggerauthentications -n visionhive

## 6. Worker Resource Requests and Limits

The ingest worker has the following resource configuration:

    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 250m
      memory: 256Mi

Requests help Kubernetes schedule pods. Limits constrain container resource consumption.

These settings do not create additional Kubernetes nodes.

## 7. KEDA Verification Status

Successfully deployed:

- KEDA operator and supporting components.
- SQS ScaledObject.
- TriggerAuthentication.
- Worker scale-to-zero configuration.
- Argo CD integration.

Observed:

- ScaledObject Ready=True.
- Target Deployment: ingest-worker.
- Worker replica count: zero when the queue was empty.
- Configured minimum replicas: zero.
- Configured maximum replicas: five.

Verification commands:

    kubectl get scaledobjects -n visionhive
    kubectl describe scaledobject ingest-worker-sqs -n visionhive
    kubectl get deployment ingest-worker -n visionhive

Important: Actual scaling under load has not yet been verified.

Pending tests:

1. Submit SQS jobs and verify worker scale-up.
2. Verify multiple worker pods process jobs.
3. Verify scale-down to zero after the queue empties.
4. Verify successful job processing and database status.
5. Test retry and failure handling.
6. Run the planned 200-job workload.

## 8. HPA versus KEDA

| Feature | HPA | KEDA |
|---|---|---|
| Main scaling signal | CPU, memory or configured metrics | Events and external metrics |
| Queue-based scaling | Requires metrics integration | Built-in queue scalers |
| Scale to zero | Not supported by standard HPA behaviour | Supported |

Interview explanation:

HPA is useful when application resource utilization determines the required number of pods.

KEDA is useful when workload demand is driven by external events. VisionHive uses SQS queue depth to determine how many ingest-worker pods are required.

## 9. Karpenter: Future AWS Architecture

Karpenter is a Kubernetes node autoscaler. It provisions and removes cloud compute capacity according to pending pod requirements.

KEDA scales application pods. Karpenter provisions Kubernetes worker nodes.

Future AWS architecture:

    Amazon EKS
       |
       +--- KEDA
       |      |
       |      +--- Amazon SQS
       |      +--- Ingest worker pod scaling
       |
       +--- Karpenter
              |
              +--- On-Demand NodePool
              |      +--- Application workloads
              |
              +--- Spot NodePool
                     +--- Worker workloads

Future NodePool design:

**On-Demand NodePool**
- API Gateway
- Upload Service
- Critical application workloads

**Spot NodePool**
- Ingest workers
- Interruptible batch workloads

The future implementation should include:

- EC2NodeClass.
- On-Demand and Spot NodePools.
- Appropriate node selectors, affinity and tolerations.
- CPU and resource limits.
- Consolidation settings.
- Karpenter controller IAM permissions.
- Subnet and security group discovery.
- An SQS interruption queue.
- EventBridge rules for EC2 interruption events.

Spot workers must support safe retries and recovery from interrupted processing.

No Karpenter NodePools, EC2NodeClasses, Spot instances or interruption queues have been deployed.

## 10. Why Karpenter Is Not Deployed on Minikube

The current Minikube environment has one local Kubernetes node.

Minikube does not provide AWS EC2 capacity or real Spot instances. Installing Karpenter locally would not demonstrate real AWS node provisioning.

The local alternative is:

- KEDA for worker pod autoscaling.
- Kubernetes requests and limits for resource control.
- The existing Minikube node and Kubernetes scheduler.

No fake Spot or On-Demand node pools are created.

Real Karpenter testing requires AWS-backed EKS and appropriate AWS permissions.

## 11. AWS Deployment Restriction

AWS Organizations Service Control Policies currently explicitly deny these operations:

- eks:CreateCluster
- eks:CreateNodegroup
- eks:CreateAddon
- eks:CreatePodIdentityAssociation

An IAM AdministratorAccess policy does not override an explicit SCP deny.

No EKS cluster was created for Phase 11.

The organization's management account must review and resolve the applicable SCP restrictions before AWS deployment.

No AWS infrastructure should be created or modified as part of the local Phase 11 implementation.

## 12. Future AWS Test Plan

After EKS permissions become available:

1. Provision an appropriate EKS cluster.
2. Configure Karpenter controller identity and IAM permissions.
3. Install Karpenter.
4. Create the EC2NodeClass.
5. Configure On-Demand and Spot NodePools.
6. Configure SQS interruption handling and EventBridge.
7. Deploy VisionHive workloads.
8. Configure KEDA with the AWS SQS queue.
9. Submit 200 jobs.
10. Observe pod scaling and node provisioning.
11. Test Spot interruption and worker recovery.
12. Verify job completion and node consolidation.

Review AWS pricing and credits before creating resources.

## 13. Verification Summary

| Component | Status |
|---|---|
| KEDA Helm installation | Installed |
| KEDA operator | Running |
| LocalStack SQS scaler | Deployed |
| TriggerAuthentication | Created |
| ScaledObject readiness | Ready |
| Worker scale-to-zero configuration | Deployed |
| Worker scale-up test | Pending |
| Worker scale-down test | Pending |
| 200-job test | Pending |
| Retry and failure tests | Pending |
| Worker resource requests and limits | Configured |
| Karpenter AWS architecture | Documented |
| Real AWS Karpenter deployment | Blocked by SCP |
| AWS Spot interruption test | Pending |

## 14. Interview Questions

**What is KEDA?**

KEDA is a Kubernetes event-driven autoscaler. It monitors external event sources such as SQS and scales application pods based on workload demand.

**Why use KEDA for VisionHive?**

Video-processing jobs arrive through SQS. Queue depth indicates pending work and is a useful signal for scaling ingest workers.

**What is the difference between KEDA and Karpenter?**

KEDA scales pods. Karpenter provisions and removes Kubernetes nodes.

**Why use EC2 Spot instances?**

Spot instances can reduce compute costs for workloads that can tolerate interruptions.

**How are Spot interruptions handled?**

Karpenter can receive interruption events through EventBridge and an SQS interruption queue. Workers should support retries and safe job recovery.

**Why was Karpenter not deployed locally?**

Minikube cannot provision AWS EC2 instances. Real Karpenter node provisioning requires AWS-backed EKS.
