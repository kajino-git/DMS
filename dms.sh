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


# DMSの設定
# タスク作成用
DATE_TIME=`date +"%Y-%m-%d:%H:%M:%S"`

# インスタンスの有無チェック
status=`aws dms describe-replication-instances | jq -r '.ReplicationInstances' | sed -e 's/\[\]//g' | wc -c`

# インスタンスが無ければインスタンスの起動
if [ $status -eq 1 ]
then
	aws dms create-replication-instance --replication-instance-identifier "replication-S3" --replication-instance-class dms.c4.2xlarge --vpc-security-group-ids sg-e4e5899d --availability-zone ap-northeast-1a --replication-subnet-group-identifier redshift-subnet --no-multi-az --auto-minor-version-upgrade --no-publicly-accessible

	sleep 5

fi

# 起動になったかの確認
count=0
while :
do
	status=`aws dms describe-replication-instances --filters Name=replication-instance-id,Values=replication-S3 | jq '.ReplicationInstances[0].ReplicationInstanceStatus' | grep "available" | wc -c`

	if [ ${status} -eq 12 ]
	then
		break
	elif [ ${count} -eq 10 ]
	then
		failed_exit "$0 error DMSinstance cannot create. Please contact to operations personnel. NUM OF COUNT=${count}minutes "	
	fi

	count=$((count+1))
	echo `date +"%Y-%m-%d:%H:%M:%S"` dmsの起動までタスクの作成を待ちます
	sleep 60
done
echo `date +"%Y-%m-%d:%H:%M:%S"` 正常に起動しました

arn=`aws dms describe-replication-instances --filters Name=replication-instance-id,Values=replication-S3 | jq '.ReplicationInstances[0].ReplicationInstanceArn' | sed -e 's/"//g'`
echo `date +"%Y-%m-%d:%H:%M:%S"` ${arn}

# ここからタスクの作成及び実行
create_task.sh

sleep 300

# タスクのステータスチェック
count=0
while :
do
	status=`aws dms describe-replication-tasks --filters "Name=replication-task-id,Values=<タスク名>" --query "ReplicationTasks[0].Status" | sed -e 's/"//g' | sed -e 's/running/runningtasks/g' | wc -c`

	if [ ${status} -eq 8 ]
        then
                break

	elif [ ${count} -eq 20 ]
	then
		failed_exit "$0 error DMStasks did not done. Please contact to operations personnel. NUM OF COUNT=${count}times waited "

        fi
	count=$((count+1))	
        echo `date +"%Y-%m-%d:%H:%M:%S"` dmsのタスク実行が完了するまで待ちます
        sleep 300

done
echo `date +"%Y-%m-%d:%H:%M:%S"` タスクの実行が完了しました

# テーブルのstatisticsにエラーが出力されていないかの確認
# テーブルエラーがあるかのチェック
# タスクの削除

def_task_arn=`aws dms describe-replication-tasks --filters "Name=replication-task-id,Values=<タスク名>" --query "ReplicationTasks[0].ReplicationTaskArn" | sed -e 's/"//g'`

table=`aws dms describe-table-statistics --replication-task-arn ${def_task_arn} | grep "Table error" | wc -l`

if [ ${table} -eq 0 ]
then
	aws dms delete-replication-task --replication-task-arn ${def_task_arn}
fi

# どれかのタスクにエラーがあった場合はshを停止する
if [ ! ${table} -eq 0 ]
then
	failed_exit "$0 error Table error arised. Please contact to operations personnel. "
fi


# タスクのステータスチェック
count=0
while :
do
        status=`aws dms describe-replication-tasks | jq -r '.ReplicationTasks' | sed -e 's/\[\]//g' | wc -c`
        if [ ${status} -eq 1 ]
        then
                break

	elif [ ${count} -eq 10 ]
	then
		failed_exit "$0 error tasks cannot delete. Please contact to operations personnel. "
        fi

	count=$((count+1))
        echo `date +"%Y-%m-%d:%H:%M:%S"` dmsのタスク削除が完了するまで待ちます
        sleep 60

done
echo `date +"%Y-%m-%d:%H:%M:%S"` タスクが正常に削除されました

# ここからレプリケーションインスタンスの削除
status=`aws dms describe-replication-instances | jq -r '.ReplicationInstances' | sed -e 's/\[\]//g' | wc -c`

if [ ${status} -ne 1 ]
then
	status=`aws dms describe-replication-instances --filters Name=replication-instance-id,Values=replication-S3 | jq '.ReplicationInstances[0].ReplicationInstanceStatus' | grep "deleting" | wc -c`

	if [ ${status} -ne 11 ]
	then

		aws dms delete-replication-instance --replication-instance-arn ${arn}
		sleep 5

	fi
fi

count=0
while :
do
	status=`aws dms describe-replication-instances | jq -r '.ReplicationInstances' | sed -e 's/\[\]//g' | wc -c`
	
	if [ ${status} -eq 1 ]
	then
		echo `date +"%Y-%m-%d:%H:%M:%S"` 正常にインスタンスが削除されました
		break
	elif [ ${count} -eq 20 ]
	then
		failed_exit "$0 error DMSinstance cannot delete. Please contact to operations personnel. "
	fi
	count=$((count+1))
	echo `date +"%Y-%m-%d:%H:%M:%S"` インスタンスを削除中です
	sleep 60
done



