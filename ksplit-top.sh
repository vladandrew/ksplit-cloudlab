#!/bin/bash 

VERBOSE_LOG=${HOME}/ksplit-verbose.log

echo "Logging to ${VERBOSE_LOG}"
./ksplit-setup.sh |& tee -a ${VERBOSE_LOG}
