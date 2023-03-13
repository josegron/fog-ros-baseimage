#!/bin/bash -eu

# generate coverity.yaml file if project doesn't already have one
# coverity.yaml.tmpl has [PROJECT_NAME] placeholder that should be replaced
# with actual project name so scan results are sent to correct stream
COVERITY_TMPL=/coverity.yaml.template
COVERITY_YAML=/main_ws/src/coverity.yaml
[[ ! -f $COVERITY_YAML ]] && \
    sed "s/\[PROJECT_NAME\]/${PROJECT_NAME}/" $COVERITY_TMPL > $COVERITY_YAML

export PATH=$PATH:/cov/bin/
cov-configure --gcc
coverity scan --exclude-language java
coverity list
