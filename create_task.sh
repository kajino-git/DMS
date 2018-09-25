#!/bin/sh

PG_HOME=<jqファイルがある絶対パス>
export JAVA_HOME=/usr/lib/jvm/jre-1.6.0
export CLASSPATH=${CLASSPATH}:${JAVA_HOME}/lib:${PG_HOME}
export PATH=${PATH}:${PG_HOME}

# SNS エラー設定
# SNS(失敗時の通知)のarn
TOPIC_ARN='SNSのトピックARNを入力'

# 失敗通知時のSubject。
TOPIC_SUBJECT='DMS Batch Autoboot failed.'

# 失敗時にmailを送るfunction
function failed_exit()
{
	MSG="***** $1 *****"
	aws sns publish --topic-arn ${TOPIC_ARN} --message "${MSG}" --subject "${TOPIC_SUBJECT}"
	echo `date +"%Y-%m-%d:%H:%M:%S"` $1
	exit 1;
}


NOW_DATE=`date +"%Y%m%d"`
base_json_file=<タスクのjsonファイルの絶対パス>
json_file=<タスクのjsonファイルディレクトリのパスと拡張子なしのファイル名>_${NOW_DATE}.json
DATE_TIME=`date +"%Y-%m-%d:%H:%M:%S"`

# インスタンスのARNを取得する
instance_arn=`aws dms describe-replication-instances --filters Name=replication-instance-id,Values=replication-S3 | jq '.ReplicationInstances[0].ReplicationInstanceArn'`

echo ${instance_arn}

# インスタンスのARN、dlスキーマ名を書き換えて当日の日付を付与
cat ${base_json_file} | sed -e 's/"arn:.*:rep:.*"/'${instance_arn}'/g' | sed -e 's/\\"dl\\"/\\"'${NOW_DATE}'\\"/g' > ${json_file}

# ARNを書き換えたファイルを使用してタスクを作成する
aws dms create-replication-task --cli-input-json file://${json_file}


# タスクの作成まで待つ
count=0
while :
do
	status=`aws dms describe-replication-tasks --filters "Name=replication-task-id,Values=<タスク名>" --query "ReplicationTasks[0].Status" | sed -e 's/"//g' | wc -c`
	if [ ${status} -eq 6 ]
	then
		break

	elif [ ${count} -eq 10 ]
	then
		failed_exit "$0 error <タスク名> cannot create. Please contact to operations personnel. NUM OF COUNT=${count}minutes "

	fi
	count=$((count+1))
	echo `date +"%Y-%m-%d:%H:%M:%S"` dmsのタスク作成が完了するまで待ちます
	sleep 60

done
echo `date +"%Y-%m-%d:%H:%M:%S"` タスクの作成が完了しました

# タスクの作成が完了したら、*/log/退避
mv ${json_file} <logファイルの絶対パス>

# 作成したタスクを開始する

task_arn=`aws dms describe-replication-tasks --filters "Name=replication-task-id,Values=<タスク名>" --query "ReplicationTasks[0].ReplicationTaskArn" | sed -e 's/"//g'`

aws dms start-replication-task --replication-task-arn ${task_arn} --start-replication-task-type start-replication

echo `date +"%Y-%m-%d:%H:%M:%S"` タスクが開始されました



