#!/bin/bash
output_dir="./test/signatures"
for CONTRACTNAME in L1ERC20Gateway L1CustomGateway L1ReverseCustomGateway L1WethGateway L2ERC20Gateway L2CustomGateway L2ReverseCustomGateway L2WethGateway L1GatewayRouter L2GatewayRouter StandardArbERC20 L1AtomicTokenBridgeCreator L1TokenBridgeRetryableSender L2AtomicTokenBridgeFactory L1OrbitCustomGateway L1OrbitERC20Gateway L1OrbitGatewayRouter L1OrbitReverseCustomGateway L1USDCGateway L1OrbitUSDCGateway L2USDCGateway
do
    echo "Checking for signature changes in $CONTRACTNAME"
    [ -f "$output_dir/$CONTRACTNAME" ] && mv "$output_dir/$CONTRACTNAME" "$output_dir/$CONTRACTNAME-old"
    forge inspect "$CONTRACTNAME" methods > "$output_dir/$CONTRACTNAME"
    diff "$output_dir/$CONTRACTNAME-old" "$output_dir/$CONTRACTNAME"
    if [[ $? != "0" ]]
    then
        CHANGED=1
    fi
done
if [[ $CHANGED == 1 ]]
then
    exit 1
fi