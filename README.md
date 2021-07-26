## OpenShift ETCD Backup

This project is a set of scripts to automate [etcd backup](https://docs.openshift.com/container-platform/4.7/backup_and_restore/backing-up-etcd.html) and run it through the native `Kubernetes Cronjob` resource. The generated backup files are transfered to an S3 bucket via [MinIO Client](https://docs.min.io/docs/minio-client-complete-guide.html).

The procedure to backup OpenShift ETCD is described here. Official guidelines from Red Hat are followed when possible. If there is any deviation, it will be detailed in this document.

At the time of writing with latest OCP version `4.7`, the default and recommended way for backing up OpenShift ETCD is described [here](https://docs.openshift.com/container-platform/4.7/backup_and_restore/backing-up-etcd.html).

**PS:** As per your organization security policies, this procedure may need modifications to be integrated to your Ops docs and processes.

## Prerequisites

- A minimum understanding of OpenShift architecture and components
- Cluster Admin access to the OpenShift Cluster
- S3 bucket with object retention enabled (to be defined as per the backup frequency)
- S3 accessKey, secretKey and endpoint to access the S3 bucket.

## Installation

To install this utility on OpenShift, you just need to leverage [this template](openshift/template.yaml).
The template parameters are:

- **OCP_ETCD_BACKUP_NAMESPACE**: The OpenShift namespace where the manifests will be created (default: `openshift-etcd-backup`)
- **OCP_ETCD_BACKUP_GIT_REPO**: The project's git repository name (default: `https://github.com/abessifi/ocp4-etcd-backup.git`)
- **OCP_ETCD_BACKUP_GIT_BRANCH**: The project's git branch name (default: `main`)
- **OCP_ETCD_BACKUP_S3_ENDPOINT**: The S3 repository url. It should start with `https`. Example: `https://foo.bar.baz`
- **OCP_ETCD_BACKUP_S3_BUCKET**: The bucket name where etcd buckups will be stored
- **OCP_ETCD_BACKUP_S3_ACCESS_KEY**: The Access key to access the S3 bucket
- **OCP_ETCD_BACKUP_S3_SECRET_KEY**: The Secret key to access the S3 bucket
- **OCP_ETCD_BACKUP_CRONJOB_SCHEDULE**: Schedule for the job specified in cron format (default: `@daily`). Default, the job will run once a day at midnight.

Once deployed, the template creates the following resources:

- A `BuildConfig` to build the `etcd-backup` container image
- An `ImageStream` to store the built image
- A `CronJob` to schedule the `etcd-backup` execution in a daily basis by default.

1. Clone the `ocp4-etcd-backup` repo:

```
$ git clone https://github.com/abessifi/ocp4-etcd-backup
```

2. Login to OCP and create the `etcd-backup` namespace:

```
$ oc login
$ oc new-project etcd-backup
```

3. Add the `privileged` SCC to the `default` service account:

```
$ oc adm policy add-scc-to-user privileged -z default -n etcd-backup
```

4. Build and deploy the etcd-backup utility:

```bash
$ cd ocp4-etcd-backup/openshift/

$ oc process -f template.yaml \
             -p OCP_ETCD_BACKUP_NAMESPACE=etcd-backup \
             -p OCP_ETCD_BACKUP_GIT_REPO=https://github.com/abessifi/ocp4-etcd-backup.git \
             -p OCP_ETCD_BACKUP_GIT_BRANCH=main \
             -p OCP_ETCD_BACKUP_S3_ENDPOINT=https://foo.bar.baz \
             -p OCP_ETCD_BACKUP_S3_ACCESS_KEY="XXXXXXXXXXXXXX" \
             -p OCP_ETCD_BACKUP_S3_SECRET_KEY="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" \
             -p OCP_ETCD_BACKUP_S3_BUCKET=foobar \
             -p OCP_ETCD_BACKUP_CRONJOB_SCHEDULE="@daily" | oc create -f -

imagestream.image.openshift.io/etcd-backup created
buildconfig.build.openshift.io/etcd-backup created
secret/minio-client-config created
cronjob.batch/etcd-backup created
```

5. Check the deployed resources:

```
$ oc get buildconfig,is,cronjob
NAME                                         TYPE     FROM          LATEST
buildconfig.build.openshift.io/etcd-backup   Docker   Git@develop   1

NAME                                         IMAGE REPOSITORY                                                           TAGS     UPDATED
imagestream.image.openshift.io/etcd-backup   image-registry.openshift-image-registry.svc:5000/etcd-backup/etcd-backup   latest   About a minute ago

NAME                        SCHEDULE       SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/etcd-backup   */15 * * * *   False     0        <none>          3m25s
```

**PS:** The etcd-backup job won't be scheduled automatically just after the cronjob creation but should be executed after some time when the schedule time constraint is reached.

## Usage

The cronjob will schedule etcd-backup execution in a regular basis, so nothing to do manually.
For troubleshooting purposes you can check the `etcd-backup` job execution as follow:

1. Grep the last job's name:

```
$ oc project etcd-backup
$ oc get jobs

NAME           COMPLETIONS   DURATION   AGE
etcd-backup-xxxx   1/1           17s        37m
```

2. Check the logs:

```
$ oc logs job/etcd-backup-xxxx
```

## Cleanup

Delete the resources that have been created by the OpenShift template:

```
$ oc adm policy remove-scc-from-user privileged -z default -n etcd-backup
$ oc delete project etcd-backup
```
