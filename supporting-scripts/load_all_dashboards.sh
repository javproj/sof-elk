#!/bin/bash
# SOF-ELK Supporting script
# (C)2016 Lewes Technology Consulting, LLC
#
# This script is used to load all dashboards, visualizations, saved searches, and index patterns to Elasticsearch

[ -r /etc/sysconfig/sof-elk ] && . /etc/sysconfig/sof-elk

ARGC=$#

es_host=localhost
es_port=9200
kibana_index=.kibana

index_patterns="httpdlog netflow syslog"

kibana_version=$( jq -r '.version' < /opt/kibana/package.json )
kibana_build=$(jq -r '.build.number' < /opt/kibana/package.json )

dashboard_list="httpd introductory netflow syslog"
dashboard_dir="/usr/local/sof-elk/dashboards/"

# enter a holding pattern until the elasticsearch server is available, but don't wait too long
max_wait=60
wait_step=0
until curl -s -XGET http://${es_host}:${es_port}/_cluster/health > /dev/null ; do
    wait_step=$(( ${wait_step} + 1 ))
    if [ ${wait_step} -gt ${max_wait} ]; then
        echo "ERROR: elasticsearch server not available for more than ${max_wait} seconds."
        exit 5
    fi
    sleep 1;
done

# create the index patterns from files
for indexid in ${index_patterns}; do
    curl -s -XDELETE http://${es_host}:${es_port}/${kibana_index}/index-pattern/${indexid}-* > /dev/null
    curl -s -XPUT http://${es_host}:${es_port}/${kibana_index}/index-pattern/${indexid}-* -T ${dashboard_dir}/index-patterns/${indexid} > /dev/null
done

# set the default index pattern, time zone, and add TZ offset to the default date format 
curl -s -XPOST http://${es_host}:${es_port}/${kibana_index}/config/${kibana_version} -d "{\"buildNum\": ${kibana_build}, \"defaultIndex\": \"syslog-*\", \"dateFormat:tz\": \"Etc/UTC\", \"dateFormat\": \"MMMM Do YYYY, HH:mm:ss.SSS Z\"}" > /dev/null

# create the dashboards, searches, and visualizations from files
for dashboard in ${dashboard_list}; do
    for type in ${dashboard_dir}${dashboard}/*; do
        type=$( basename $type )

        for object in ${dashboard_dir}${dashboard}/${type}/*; do
            object=$( basename ${object} )
            curl -s -XDELETE http://${es_host}:${es_port}/${kibana_index}/${type}/${object} > /dev/null
            curl -s -XPUT http://${es_host}:${es_port}/${kibana_index}/${type}/${object} -T ${dashboard_dir}${dashboard}/${type}/${object} > /dev/null
        done
    done
done

# # prevent this script from automatically running again on next boot
# # ignore this if being forced
# if [ ${FORCE} != "force" ]; then
#     TMPFILE=$( mktemp )
#     grep -v ^reset_dashboards /etc/sysconfig/sof-elk > ${TMPFILE}
#     echo "reset_dashboards=0" >> ${TMPFILE}
#     cat ${TMPFILE} > /etc/sysconfig/sof-elk
#     rm -f ${TMPFILE}
# fi
