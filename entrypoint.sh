#!/bin/bash

# Exit if the bucket name is not defined
if [[ -z "$S3_BUCKET_NAME" ]]; then
    echo "[ERROR] The S3 bucket name is not provided"
    exit 1
fi

# Init mc config from mounted secret
echo "[INFO] Copy MinIO config file"
cp /etc/mc/config.json /root/.mc/config.json

# Run the cluster-backup.sh script
echo "[INFO] Start etcd backup.."
chroot /host /usr/local/bin/cluster-backup.sh /home/core/assets/backup

# Exit if no backup files generated
find /host/home/core/assets/backup -maxdepth 0 -empty -exec echo "[ERROR] {} is empty" \; || exit 1
echo "[INFO] Etcd backup files generated !"

# Upload the backed up artifacts
# TODO: Detect upload errors and "exit 1"
echo "[INFO] Copy backup files to S3.."
for file_name in `ls /host/home/core/assets/backup`; do
  mc cp --quiet --md5 /host/home/core/assets/backup/$file_name s3-repo/$S3_BUCKET_NAME/
done

# cleanup the local backup dir if upload is ok
if [ $? == 0 ]; then
  echo "[INFO] Etcd backup finished !"
  echo "[INFO] Cleanup local backup directory.."
  rm -rf /host/home/core/assets/backup/*
fi

exit 0
