#!/bin/bash 

VERBOSE_LOG=${HOME}/ksplit-verbose.log

echo "Logging to ${VERBOSE_LOG}"
/local/repository/ksplit-setup.sh |& tee -a ${VERBOSE_LOG}
