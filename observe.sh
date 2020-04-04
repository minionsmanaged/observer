#!/bin/bash

# add to cron if not in cron list
crontab -l | grep $0 || (crontab -l ; echo "*/5 * * * * $0") | crontab -
mkdir -p ${HOME}/cron/log/minionsmanaged-observer

regions=(eu-central-1 us-east-1 us-west-1 us-west-2)

tmp_dir=$(mktemp -d)

git clone git@github.com:minionsmanaged/observations.git ${tmp_dir}/observations >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log

for region in ${regions[@]}; do
  aws ec2 describe-instances --region ${region} --filters Name=tag:ManagedBy,Values=taskcluster Name=instance-state-name,Values=running --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,ImageId:ImageId,WorkerPool:Tags[?Key==`Name`]|[0].Value,AvailabilityZone:Placement.AvailabilityZone,LaunchTime:LaunchTime,PublicIpAddress:PublicIpAddress,InstanceLifecycle:InstanceLifecycle}' | jq '[.[][]]' > ${tmp_dir}/${region}.json
  echo "${region}: $(jq '. | length' ${tmp_dir}/${region}.json | head -1) running instances in $(jq -r '[[.[] | .WorkerPool] | unique | sort | .[]] | length' ${tmp_dir}/${region}.json) pools" >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log
  workerPools=$(jq -r '[.[] | .WorkerPool] | unique | sort | .[]' ${tmp_dir}/${region}.json)
  for workerPool in ${workerPools[@]}; do
    echo "${region}/${workerPool}: $(jq --arg workerPool ${workerPool} '[.[] | select(.WorkerPool == $workerPool)] | length' ${tmp_dir}/${region}.json | head -1) running instances" >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log
  done
done
jq '.[]' ${tmp_dir}/*.json | jq -s '. |= sort_by(.LaunchTime)' > ${tmp_dir}/all.json
echo "all regions: $(jq '. | length' ${tmp_dir}/all.json | head -1) running instances in $(jq -r '[[.[] | .WorkerPool] | unique | sort | .[]] | length' ${tmp_dir}/all.json) pools" >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log
workerPools=$(jq -r '[.[] | .WorkerPool] | unique | sort | .[]' ${tmp_dir}/all.json)
for workerPool in ${workerPools[@]}; do
  echo "all regions/${workerPool}" >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log
  echo "all regions/${workerPool}: $(jq --arg workerPool ${workerPool} '[.[] | select(.WorkerPool == $workerPool)] | length' ${tmp_dir}/all.json | head -1) running instances" >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log
  mkdir -p ${tmp_dir}/observations/workers/${workerPool}
  instance_id_list=$(jq -r --arg workerPool ${workerPool} '[.[] | select(.WorkerPool == $workerPool) | .InstanceId] | unique | sort | .[]' ${tmp_dir}/all.json)
  for instance_id in ${instance_id_list[@]}; do
    if [ ! -f ${tmp_dir}/observations/workers/${workerPool}/${instance_id}.json ]; then
      jq --arg instanceId ${instance_id} '.[] | select(.InstanceId == $instanceId)' ${tmp_dir}/all.json > ${tmp_dir}/observations/workers/${workerPool}/${instance_id}.json
    fi
  done
done
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations config diff.renames false
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations pull >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations add . -A >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations commit -m "observations of running instances in aws" >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log
git --git-dir=${tmp_dir}/observations/.git --work-tree=${tmp_dir}/observations push origin master >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log

rm -Rf ${tmp_dir} >> ${HOME}/cron/log/minionsmanaged-observer/$(/usr/bin/date -u '+%Y-%m-%d').log
