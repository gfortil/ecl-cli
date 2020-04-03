# Original soap call input file
QUERY_LIST_FILENAMES=nonfcra_online_requests.xml

# File is too long. Creates a shortlist.
QUERY_SHORTLIST_FILENAME=nonfcra_online_requests_shortlist.xml

# Merge multiple soap call input files to create a fusion 
FUSIONQ=(${QUERY_SHORTLIST_FILENAME} 'query_list_bob.xml')

FUSIONQ_FILENAME=fusionq.xml

RISKUSR=
TEST_DIR=/mnt/disk1/home/${RISKUSR}/nightly_test
SOURCE_ESP=
SOURCE_DALI=
SOURCE_CLUSTER=
TARGET_CLUSTER=
RECURRENCE=1
TOTAL_Q=0
UNIQUE_Q=0
TMP_LIST=query_list.txt

create_shortlist () {
  if [ -e ${TEST_DIR}/${QUERY_SHORTLIST_FILENAME} ]; then rm ${TEST_DIR}/${QUERY_SHORTLIST_FILENAME}; fi
    
  while IFS= read -r line
  do
    cat ${TEST_DIR}/${QUERY_LIST_FILENAMES} | grep --max-count=1 $line | tee -a ${TEST_DIR}/${QUERY_SHORTLIST_FILENAME}
  done < ${TMP_LIST}
}

create_fusion_file () {
  if [ -e ${TEST_DIR}/${FUSIONQ_FILENAME} ];then rm ${TEST_DIR}/${FUSIONQ_FILENAME}; fi
  for filename in ${FUSIONQ[@]}
  do
     cat ${TEST_DIR}/${filename} | tee -a ${TEST_DIR}/${FUSIONQ_FILENAME}
  done
}

count_total_queries () {

    local i=${RECURRENCE}
    local input="${TEST_DIR}/$1"

    if [[ -f ${input} ]]
    then
        while IFS= read -r line
        do
          ((++UNIQUE_Q))
        done < ${input}
        TOTAL_Q=$(( $UNIQUE_Q * $RECURRENCE ))
    else
        echo "Unable to find ${input} file"
        exit 1;
    fi
}

# gets a list of all active queries on a foreign env and save the query ids and wuids in a txt file
get_query_list () {

    echo "Getting the list of unique queries..."

    local input="${TEST_DIR}/$1"

    if [[ -f ${input} ]]
    then
        if [[ -e ${TMP_LIST} ]]
        then 
            rm ${TMP_LIST} 
            touch ${TMP_LIST}
        else 
            touch ${TMP_LIST}
        fi
            
        while IFS= read -r line
        do
            local qid=$(echo ${line} | awk '{print $1}' | sed 's?<??g')
            local query_id=${qid}
			
            if [[ -n $(echo ${qid} | awk '/>/') ]] && [[ $(echo ${qid} | awk '/>/')==${qid} ]]
            then
                query_id=$(echo $qid | sed 's?>? ?' | awk '{print $1}')
                
            elif [[ -n $(echo ${qid} | awk '/Request/') ]] && [[ $(echo ${qid} | awk '/Request/')==${qid} ]]
            then
                #query_id=$(echo ${line} | sed 's?Request??')
                query_id=$(echo ${qid} | sed 's?Request??')
            fi


            if [[ ! -n $(awk "/${query_id}/" ${TMP_LIST} ) ]]
            then
                echo ${query_id} >> ${TMP_LIST}
            fi
        done < ${input}
    else
        echo "Unable to find ${input} file"
        exit 1;
    fi
}

# Copies queries from a foreign env to a local env based on xml or txt file 
copy_query_list () {

    echo "Copying the list of queries from ${SOURCE_CLUSTER}..."

    if [[ -f ${TMP_LIST} ]]
    then
        while IFS= read -r query
        do
            ecl queries copy //${SOURCE_ESP}:8010/${SOURCE_CLUSTER}/${query} -u="${USR}" -pw="${PSWD}" ${TARGET_CLUSTER} --daliip=${SOURCE_DALI} -v -A --allow-foreign ||true
        done < ${TMP_LIST}
    else
        echo "Unable to find ${TMP_LIST} file"
        exit 1;
    fi
}

# publish queries from xml or txt input file to WSECL
publish_query_list () {

    echo "Publishing the list of queries to WSECL..."

    local input="${TEST_DIR}/$1"

    if [[ -f ${input} ]]
    then
        while IFS= read -r query
        do
            ecl publish ${TARGET_CLUSTER} ${query} -v -A -u="${USR}" -pw="${PSWD}" --wait-read=120 || true 
        done < ${TMP_LIST}
    else
        echo "Unable to find ${input} file"
        exit 1;
    fi
}

# Recompiles all queries from xml or txt input file
recreate_query_list () {

    echo "Recreating the list of queries..."

    if [[ -f ${TMP_LIST} ]]
    then
        while IFS= read -r query
        do
            ecl queries recreate ${TARGET_CLUSTER} ${query} -u="${USR}" -pw="${PSWD}" -A -v --daliip=${SOURCE_DALI} || true
        done < ${TMP_LIST}
    else
        echo "Unable to find ${TMP_LIST} file"
        exit 1;
    fi
}

# Runs all queries from input file
run_query_list () {
    
    echo "Running the list of queries on ${TARGET_CLUSTER}..."
    local i=${RECURRENCE}
    
    while [ ${i} -ge 1 ]
    do
        ((++rec))
        
        local input="${TEST_DIR}/$1"
        
        if [[ -f ${input} ]]
        then
            while IFS= read -r line
            do
                local qid=$(echo ${line} | awk '{print $1}' | sed 's?<??g')
                local query_id=${qid}
				
                if [[ -n $(echo ${qid} | awk '/>/') ]] && [[ $(echo ${qid} | awk '/>/')==${qid} ]]
                then
                    query_id=$(echo $qid | sed 's?>? ?' | awk '{print $1}')
                elif [[ -n $(echo ${qid} | awk '/Request/') ]] && [[ $(echo ${qid} | awk '/Request/')==${qid} ]]
                then
                    query_id=$(echo ${qid} | sed 's?Request??')
                fi

                if [[ -e ${TEST_DIR}/query_input.xml ]]
                then
                	echo '<?xml version="1.0" encoding="UTF-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/">' | tee ${TEST_DIR}/query_input.xml
                    echo '<soap:Body>' | tee -a ${TEST_DIR}/query_input.xml
                    echo "	${line}" | tee -a ${TEST_DIR}/query_input.xml
                    echo '</soap:Body>' | tee -a ${TEST_DIR}/query_input.xml
                    echo '</soap:Envelope>' | tee -a ${TEST_DIR}/query_input.xml
                    #sed -i "s~$(awk 'NR==4' ${TEST_DIR}/query_input.xml)~${line}~" ${TEST_DIR}/query_input.xml                  
                fi
                
                ((++count))
                
                echo "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
                echo "::::::--->  Running query: ${count} | Current Iteration: ${rec} | Total Iterations: ${RECURRENCE} | Total Unique Queries: ${UNIQUE_Q} | Total Queries to run: ${TOTAL_Q} <---::::::"
                echo "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"

                soapplus -url http://${USR}:"${PSWD}"@10.173.160.101:8002/WsEcl/proxy/query/${TARGET_CLUSTER}/${query_id} -i "${TEST_DIR}/query_input.xml" || true
                #soapplus -url http://${USR}:"${PSWD}"@10.173.160.101:8002/WsEcl/soaprun/query/${TARGET_CLUSTER}/${query_id} -i "${TEST_DIR}/query_input.xml" || true
                #soapplus -stress 4 1 -url http://${USR}:"${PSWD}"@10.173.160.101:8002/WsEcl/proxy/query/${TARGET_CLUSTER}/${r} -i "${line}"
            done < ${input}
        
            ((i--))
        else
            echo "Unable to find ${input} file"
            exit 1;
        fi
    done

}

# Call the functions in order

#create_shortlist
#create_fusion_file
#get_query_list ${FUSIONQ_FILENAME}
count_total_queries ${FUSIONQ_FILENAME}
#copy_query_list ${FUSIONQ_FILENAME}
#recreate_query_list ${FUSIONQ_FILENAME}
#publish_query_list ${FUSIONQ_FILENAME}
run_query_list ${FUSIONQ_FILENAME}

