#!/bin/bash
if [[ $PWD == */token-bridge-contracts ]];
    then $npm_execpath run hardhat compile;
    else $npm_execpath run hardhat:prod compile;
fi
