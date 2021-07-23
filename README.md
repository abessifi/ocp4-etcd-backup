## OpenShift ETCD Backup

This project is a set of scripts to automate [etcd backup](https://docs.openshift.com/container-platform/4.7/backup_and_restore/backing-up-etcd.html) and run it through the native `Kubernetes Cronjob` resource.

The procedure to backup OpenShift ETCD is described here. Official guidelines from Red Hat are followed when possible. If there is any deviation, it will be detailed in this document.

At the time of writing with latest OCP version `4.7`, the default and recommended way for backing up OpenShift ETCD is described [here](https://docs.openshift.com/container-platform/4.7/backup_and_restore/backing-up-etcd.html).

**PS:** As per your organization security policies, this procedure may need modifications to be integrated to your Ops docs and processes.

## Prerequisites

- A minimum understanding of OpenShift architecture and components
- Cluster Admin access to the OpenShift Cluster
- S3 bucket with object retention enabled (to be defined as per the backup frequency)
- S3 accessKey, secretKey and endpoint to access the S3 bucket.

## Installation

To install this utility on OpenShift, you just need to leverage [this template](openshift/template.yaml). The template parameters are:

- **OCP_INSTALLER_SECRET_NAME**: The secret name that holds the SA key to be rotated (default: `gcp-credentials`)
- **OCP_INSTALLER_SECRET_NAMESPACE**: The OpenShift namespace name where the secret is (default: `kube-system`)
- **GCP_SERVICEACCOUNT_KEY_EXPIRATION_PERIOD**: The renewal period of the GCP Key (default: `90` days)
- **LOGGING_LEVEL**: The keyrotator log level (default: `INFO`)

Once deployed, the template creates the following resources:

- A `BuildConfig` to build the `keyrotator` container image using a `Python` base image
- An `ImageStream` to store the built image
- A `Service Account` with a custom `Role` and `RoleBinding`
- A `CronJob` to schedule the keyrotator execution in a `daily` basis.

1. Clone the `scale-gcp-keyrotator` repo:

```
$ git clone ssh://git@emea-aws-gitlab.sanofi.com:2222/scale/team/scale-gcp-keyrotator.git

or

$ git clone https://<gitlab-username>:<gitlab-access-token>@emea-aws-gitlab.sanofi.com:3001/scale/team/scale-gcp-keyrotator.git
```

2. Login to OCP and switch to the `kube-system` namespace:

```
$ oc login
$ oc project kube-system
```

3. Create the `gitlab-credentials` secret with credentials for checking out the project from gitlab

```
$ oc create secret generic gitlab-credentials \
    --from-literal=username=<gitlab-username> \
    --from-literal=password=<gitlab-access-token> \
    --type=kubernetes.io/basic-auth
```

4. Build and deploy keyrotator:

```bash
$ cd scale-gcp-keyrotator/openshift/

# Build with default configuration
$ oc process -f template.yaml | oc create -f -

serviceaccount/keyrotator created
role.rbac.authorization.k8s.io/gcp-credentials-secret-handler created
rolebinding.rbac.authorization.k8s.io/gcp-credentials-handler created
imagestream.image.openshift.io/keyrotator created
buildconfig.build.openshift.io/keyrotator created
cronjob.batch/keyrotator created

# Or build with custom configuration like running the app in debug mode and setting the
# key renewal period to '60 days' instead of the default value which is '90 days'
$ oc process -f template.yaml -p LOGGING_LEVEL=DEBUG -p GCP_SERVICEACCOUNT_KEY_EXPIRATION_PERIOD=60
```

5. Check the deployed resources:

```
$ oc get buildconfig,is,cronjob
NAME                                        TYPE     FROM   LATEST
buildconfig.build.openshift.io/keyrotator   Docker   Git    1

NAME                                        IMAGE REPOSITORY                                                                                                      TAGS     UPDATED
imagestream.image.openshift.io/keyrotator   default-route-openshift-image-registry.apps.scale-bbd75801.p673311018045.gcp-emea.sanofi.com/kube-system/keyrotator   latest   About an hour ago

NAME                       SCHEDULE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/keyrotator   @daily     False     0        <none>          90m
```

**PS:** The keyrotator job won't be scheduled automatically just after the cronjob creation but should be executed after some time when the `daily` time constraint is reached.

### Usage

The cronjob will schedule keyrotator execution in a daily basis, so nothing to do manually.
For troubleshooting purposes you can check the `keyrotator` execution as follow:

1. Grep the last job's name:

```
$ oc project kube-system
$ oc get jobs

NAME           COMPLETIONS   DURATION   AGE
keyrotator-xxxx   1/1           17s        37m
```

2. Check the logs:

```
$ oc logs job/keyrotator-xxxx
```

### Cleanup

1. Delete the resources that have been created by the OpenShift template:

```
$ oc project kube-system
$ cd scale-gcp-keyrotator/openshift/
$ oc process -f template.yaml | oc delete -f -
```

2. Delete the `gitlab-credentials` secret:

```
$ oc delete secret gitlab-credentials
```

## Other Service Accounts Keys Rotation

The OCP platform Operators also leverages IAM Service Accounts in order to interact with specific GCP APIs. The Service Accounts Keys should also be rotated in a regular basis to enforce cluster security and be compliant we the security policy.

When you get a request/notification from the CloudOps team, you can follow the following steps in order to rotate those keys.

1. Make sure the `Installer Service Account` has already the roles `Service Account Admin` and `Service Account Key Admin`.
You can check this using the `gcloud` CLI or via the `GCP Web Console` on the `IAM` section.

```
$ gcloud projects get-iam-policy <YOUR GCLOUD PROJECT>  \
--flatten="bindings[].members" \
--format='table(bindings.role)' \
--filter="bindings.members:<YOUR SERVICE ACCOUNT>"

ROLE
roles/compute.admin
roles/dns.admin
roles/iam.securityAdmin
roles/iam.serviceAccountAdmin
roles/iam.serviceAccountKeyAdmin
roles/iam.serviceAccountUser
roles/storage.admin
```

2. List the active `CredentialRequests` resources:

```
for cr in $(oc -n openshift-cloud-credential-operator get credentialsrequest --no-headers -o name); do
  sa=$(oc -n openshift-cloud-credential-operator get $cr -o jsonpath='{.status.providerStatus.serviceAccountID}');
  if [ ! -z "$sa" ]; then
    awk -F'/' '{ print $2 }' <<< $cr;
  fi
done
```

Basically you should get the following output:

```
openshift-image-registry-gcs
openshift-ingress-gcp
openshift-machine-api-gcp
```

3. Delete the `CredentialRequests` one by one and check the status of the new created ones:

```bash
# Delete the 'openshift-image-registry-gcs' resource
$ oc -n openshift-cloud-credential-operator delete credentialsrequest openshift-image-registry-gcs
# Wait a couple of minutes and check the status. It should be 'true'.
$ oc -n openshift-cloud-credential-operator get credentialsrequest openshift-image-registry-gcs -o jsonpath='{.status.provisioned}{"\n"}'
# Restart registry pods
$ for pd in $(oc get pods -n openshift-image-registry -l docker-registry=default --no-headers -o name); do oc -n openshift-image-registry delete $pd; sleep 5; done

# Delete the 'openshift-ingress-gcp' resource
$ oc -n openshift-cloud-credential-operator delete credentialsrequest openshift-ingress-gcp
# Wait a couple of minutes and check the status. It should be 'true'.
$ oc -n openshift-cloud-credential-operator get credentialsrequest openshift-ingress-gcp -o jsonpath='{.status.provisioned}{"\n"}'
# Restart the Ingress Operator
$ oc -n openshift-ingress-operator delete pod -l name=ingress-operator

# Delete the 'openshift-machine-api-gcp' resource
$ oc -n openshift-cloud-credential-operator delete credentialsrequest openshift-machine-api-gcp
# Wait a couple of minutes and check the status. It should be 'true'.
$ oc -n openshift-cloud-credential-operator get credentialsrequest openshift-machine-api-gcp -o jsonpath='{.status.provisioned}{"\n"}'
```

4. Check the status of all `Cluster Operators` and make sure none of them is degraded:

```
$ oc get clusteroperators

NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE
authentication                             4.6.8     True        False         False      11h
cloud-credential                           4.6.8     True        False         False      141d
cluster-autoscaler                         4.6.8     True        False         False      141d
config-operator                            4.6.8     True        False         False      35d
console                                    4.6.8     True        False         False      3h25m
csi-snapshot-controller                    4.6.8     True        False         False      20d
dns                                        4.6.8     True        False         False      35d
etcd                                       4.6.8     True        False         False      141d
image-registry                             4.6.8     True        False         False      5h34m
ingress                                    4.6.8     True        False         False      35d
insights                                   4.6.8     True        False         False      141d
kube-apiserver                             4.6.8     True        False         False      141d
kube-controller-manager                    4.6.8     True        False         False      141d
kube-scheduler                             4.6.8     True        False         False      141d
kube-storage-version-migrator              4.6.8     True        False         False      20d
machine-api                                4.6.8     True        False         False      141d
machine-approver                           4.6.8     True        False         False      35d
machine-config                             4.6.8     True        False         False      20d
marketplace                                4.6.8     True        False         False      20d
monitoring                                 4.6.8     True        False         False      20d
network                                    4.6.8     True        False         False      141d
node-tuning                                4.6.8     True        False         False      35d
openshift-apiserver                        4.6.8     True        False         False      20d
openshift-controller-manager               4.6.8     True        False         False      35d
openshift-samples                          4.6.8     True        False         False      35d
operator-lifecycle-manager                 4.6.8     True        False         False      141d
operator-lifecycle-manager-catalog         4.6.8     True        False         False      141d
operator-lifecycle-manager-packageserver   4.6.8     True        False         False      20d
service-ca                                 4.6.8     True        False         False      141d
storage                                    4.6.8     True        False         False      35d
```
