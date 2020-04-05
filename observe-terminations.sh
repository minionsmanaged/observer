#!/bin/bash

echo "[observe-terminations $(date --utc +"%F %T.%3NZ")] execution initiated" >> ${HOME}/cron/log/minionsmanaged-observer/$(date -u '+%Y-%m-%d-%H').log

# add to cron if not in cron list
crontab -l | grep $0 || (crontab -l ; echo "*/3 * * * * $0") | crontab -
mkdir -p ${HOME}/cron/log/minionsmanaged-observer

regions=(eu-central-1 us-east-1 us-west-1 us-west-2)

tmp_dir=$(mktemp -d)

git clone git@github.com:minionsmanaged/observations.git ${tmp_dir}/observations >> ${HOME}/cron/log/minionsmanaged-observer/$(date -u '+%Y-%m-%d-%H').log
for region in ${regions[@]}; do
  aws ec2 describe-instances --region ${region} --filters Name=tag:ManagedBy,Values=taskcluster Name=instance-state-name,Values=running --query 'Reservations[*].Instances[*].InstanceId' | jq -r '.[][]' >> ${tmp_dir}/running-instances.txt
done
shopt -s globstar
workerPaths=(${tmp_dir}/observations/workers/**/*.json)
for workerPath in ${workerPaths[@]}; do
  workerFileBasename=$(basename -- ${workerPath})
  workerInstanceId="${workerFileBasename%.*}"
  if ! grep -q ${workerInstanceId} ${tmp_dir}/running-instances.txt; then
    rm -f ${workerPath}
    echo "[observe-terminations $(date --utc +"%F %T.%3NZ")] removing ${workerPath}" >> ${HOME}/cron/log/minionsmanaged-observer/$(date -u '+%Y-%m-%d-%H').log
  fi
done
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations config diff.renames false
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations pull >> ${HOME}/cron/log/minionsmanaged-observer/$(date -u '+%Y-%m-%d-%H').log
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations add . -A >> ${HOME}/cron/log/minionsmanaged-observer/$(date -u '+%Y-%m-%d-%H').log
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations commit -m "observations of removed instances in aws" >> ${HOME}/cron/log/minionsmanaged-observer/$(date -u '+%Y-%m-%d-%H').log
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations push origin master >> ${HOME}/cron/log/minionsmanaged-observer/$(date -u '+%Y-%m-%d-%H').log

rm -Rf ${tmp_dir}

# delete logs more than 10 days old
/usr/bin/find ${HOME}/cron/log/minionsmanaged-observer -mtime +10 -type f -delete

echo "[observe-terminations $(date --utc +"%F %T.%3NZ")] execution complete" >> ${HOME}/cron/log/minionsmanaged-observer/$(date -u '+%Y-%m-%d-%H').log
