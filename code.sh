#!/bin/bash
#####################################################
# 说明: 代码上线的脚本
# 调用方式: code.sh (release|product) proj_name branch_name [tag_name|commit_id]
# 把 proj项目指定的分支和tag上线到release环境
# 
# 需要把这台机器的公钥放到发布机器上，实现免密登录
# 需要把公钥放到gitlab，可以免密git clone 代码
# auth: yuyongpeng@hotmail.com
#####################################################


#####################################################
# 配置说明
#####################################################
#### 命令行参数
MODE=$1                                     # release or product
PROJ_NAME=$2                                # 项目名称
BRANCH_NAME=${3:-master}                    # 分支的名称（默认master分支）
COMMIT_OR_TAG=0                             # 0:COMMIT ; 1:TAG
if [[ ${#4} -gt 30 ]];then
    COMMIT_ID=$4                            # commit id
    COMMIT_OR_TAG=0
else 
    TAG_NAME=$4                             # 版本号
    COMMIT_OR_TAG=1
fi

# if [[ $# < 4 ]];then
#     echo "Incorrect parameters"
#     echo "code.sh release|product proj_name branch_name tag_name"
#     echo "OR"
#     echo "code.sh release|product proj_name branch_name commit_id"
#     exit
# fi


#### 配置信息
RELEASE_SERVER=release_host                 # release-application服务器在hosts里面的名称
CODE_PATH=/data/code                        # 代码保存的路径
PUBLISH_PATH=/HC/HTML                       # 发布到服务器上的路径
BACKUP_PATH=/data/code_backup/${PROJ_NAME}  # 代码每一次发布的备份路径
BACKUP_PRODUCT_PATH=${BACKUP_PATH}/product  # 生产环境的代码本地备份路径
BACKUP_RELEASE_PATH=${BACKUP_PATH}/release  # release环境的代码本地备份路径
#### 每一个项目发布到对应的服务器
mobile_HOSTS=( web-server-1 )
www_HOSTS=( web-server-1 )
dphotos_HOSTS=( web-server-1 )
mobile_EXTS=( .git .gitignore )
www_EXTS=( .git .gitignore )
dphotos_EXTS=( .git .gitignore )


#####################################################
# 常用命令的封装
#####################################################
#获取字符串的日期时间,格式如20180914094044：2018年9月14日9点40分44秒
g_curTime=$(date "+%Y%m%d%I%M%S")
# rsync -artvz $gitSourcePath --exclude=$excludeArray root@inhouse-web-server-1:$topath;

#####################################################
# 解析配置参数
#####################################################
parse_server_arguments() {
  for arg do
    case "$arg" in
      --branch=*)  
        BRANCH_NAME=`echo "$arg" | sed -e 's/^[^=]*=//'`
        ;;
      --tag=*)  
        TAG_NAME=`echo "$arg" | sed -e 's/^[^=]*=//'`
        ;;
      --commit=*) 
        COMMIT_ID=`echo "$arg" | sed -e 's/^[^=]*=//'` 
        ;;
    esac
  done
}
#####################################################
# 每一个命令对应的函数调用
#####################################################

rsync_code(){
    proj=$1
    host=$2
    # 将需要排除的目录编排成字符串
    eval exts=\(\${${proj}_EXTS[*]}\)
    for ext in ${exts[@]};do
        excludeString="$excludeString --exclude $ext"
    done
    echo "上线代码的动作："
    echo "rsync -e 'ssh -p 2345' -artvz $CODE_PATH/$PROJ_NAME $excludeString root@$host:$PUBLISH_PATH"
    rsync -e 'ssh -p 2345' -artz $CODE_PATH/$PROJ_NAME $excludeString root@$host:$PUBLISH_PATH
    # 代码同步完毕后需要执行的附加命令
    case "$proj" in 
        'mobile')
            echo "代码同步完成后执行的附加命令："
            if [[ $MODE == "release" ]];then
                echo "ssh -p 2345 $host \"cd /HC/HTML/mobile; source /etc/profile; npm run release\""
                ssh -p 2345 $host "cd /HC/HTML/mobile; source /etc/profile; npm run release"
                #ssh -p 2345 $host /etc/test.sh
            fi
            if [[ $MODE == "product" ]];then
                echo "ssh -p 2345 $host \"cd /HC/HTML/mobile; source /etc/profile; npm install --unsafe-perm=true --allow-root; npm run build\""
                ssh -p 2345 $host "cd /HC/HTML/mobile; source /etc/profile; npm install --unsafe-perm=true --allow-root; npm run build"
                #ssh -p 2345 $host /etc/test.sh
            fi
        ;;
        'dphotos')
            echo "dphotos"
        ;;
    esac
}

git_update(){
    echo "更新git仓库(${CODE_PATH}/${PROJ_NAME})到指定的branch=(${BRANCH_NAME})、tag=(${TAG_NAME})、commit=(${COMMIT_ID})"
    cd ${CODE_PATH}/${PROJ_NAME}
    git stash
    git pull
    git checkout ${BRANCH_NAME}
    # 2个变量都没有值
    if [[ ! -n ${TAG_NAME} && ! -n ${COMMIT_ID} ]];then
        branch_count=`git branch -a | grep origin | grep ${BRANCH_NAME} | wc -l`
        if [[ $branch_count -ge 1 ]];then
            echo "更新的是 ${BRANCH_NAME} 分支的最新commit"
            git checkout ${BRANCH_NAME}
        else
            echo -e "\033[31m ****** ERROR: ****** \033[0m"
            echo "项目：${PROJ_NAME}, BRANCH=${BRANCH_NAME} 不存在，暂停更新动作"
            exit
        fi
    elif [[ -n ${TAG_NAME} ]];then
        tag_count=`git tag | grep ${TAG_NAME} | wc -l`
        if [[ $tag_count -eq 1 ]];then
            echo "更新的是 ${BRANCH_NAME} 分支的 TAG=${TAG_NAME}"
            git checkout ${TAG_NAME}
        else
            echo -e "\033[31m ****** ERROR: ****** \033[0m"
            echo "项目：${PROJ_NAME}, TAG=${TAG_NAME} 不存在，暂停更新动作"
            if [[ $COMMIT_OR_TAG -eq 1 ]];then
                # 0:COMMIT ; 1:TAG
                exit
            fi
        fi
    elif [[ -n ${COMMIT_ID} ]];then
        commit_count=`git log | grep ${COMMIT_ID} | wc -l`
        if [[ $commit_count -eq 1 ]];then
            echo "更新的是 ${BRANCH_NAME} 分支的 COMMIT_ID=${COMMIT_ID}"
            git reset --hard ${COMMIT_ID}
        else
            echo -e "\033[31m ****** ERROR: ****** \033[0m"
            echo "项目：${PROJ_NAME}, COMMIT_ID=${COMMIT_ID} 不存在，暂停更新动作"
            if [[ $COMMIT_OR_TAG -eq 0 ]];then
                # 0:COMMIT ; 1:TAG
                exit
            fi
        fi
    fi
}

# 备份release-server上的代码到本地
backup_release_date(){
    proj=$1
    mkdir -p $BACKUP_RELEASE_PATH/${proj}_$g_curTime
    echo "备份代码到本地 (带有时间的后缀)"
    echo "rsync -e 'ssh -p 2345' -artz root@$RELEASE_SERVER:$PUBLISH_PATH/$proj/* $BACKUP_RELEASE_PATH/${proj}_$g_curTime/*"
    rsync -e 'ssh -p 2345' -artz root@$RELEASE_SERVER:$PUBLISH_PATH/$proj/* $BACKUP_RELEASE_PATH/${proj}_$g_curTime/*
}
backup_release(){
    proj=$1
    mkdir -p $BACKUP_RELEASE_PATH/${proj}/
    echo "备份代码到本地"
    echo "rsync -e 'ssh -p 2345' -artz root@$RELEASE_SERVER:$PUBLISH_PATH/$proj/* $BACKUP_RELEASE_PATH/${proj}/*"
    rsync -e 'ssh -p 2345' -artz root@$RELEASE_SERVER:$PUBLISH_PATH/$proj/* $BACKUP_RELEASE_PATH/${proj}/*
}
# 备份生产环境的代码
backupd_product(){
    echo "test"
}

# 初始化gitlab中的代码到本地
init_code(){
	cd ${CODE_PATH}
	git clone git@gitlab.hard-chain.cn:hardware/dphoto-mobile.git ${CODE_PATH}/mobile
}

# 上线代码到release环境
release(){
    # 先备份release_host上的代码
    # backup_release_date $PROJ_NAME
    # 更新代码
    git_update
    # 代码上线
    echo "项目: ${PROJ_NAME} 代码上线 -> server($RELEASE_SERVER)"
    rsync_code $PROJ_NAME $RELEASE_SERVER
}

# 上线代码到product环境
product(){
    # 把release的代码拷贝到本地
    # backup_release $PROJ_NAME
    echo "代码上线到 product 环境"
    # 代码上线
    eval servers=\(\${${PROJ_NAME}_HOSTS[*]}\)
    for host in ${servers[@]};do
        echo "项目: ${PROJ_NAME} 代码上线 -> server($host)"
        rsync_code $PROJ_NAME $host
    done
}
# 回滚product代码
rollback_product(){
    echo "rollback_product";
}
# 回滚release代码
rollback_release(){
    echo "rollback_release";
}


#####################################################
# 入口总程序
#####################################################
case "$MODE" in
  	'init_code')
    # 初始化gitlab中的代码到本地
    init_code
    ;;

  	'release')
    # 上线代码到release环境
    release
    ;;

  	'product')
	# 上线代码到product环境
	product
    ;;

    'rollback_product')
	# 回滚product代码
	rollback_product
    ;;

    'rollback_release')
	# 回滚release代码
	rollback_release
    ;;

    *)
      # usage
      basename=`basename "$0"`
      echo "Usage: $basename {release|product} proj_name branch_name [tag_name|commit_id]"
      exit 1
    ;;
esac
