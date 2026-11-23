#!/bin/bash

# push the toml
composer-cli blueprints push edge9.toml

# ensure things look good
composer-cli blueprints list
composer-cli blueprints show edge9

# ensure all packages can be installed
composer-cli blueprints depsolve edge9

# create the initial image
composer-cli compose start edge9 edge-commit

# create the iso istaller
composer-cli compose start-ostree edge9 edge-installer
