package staker

import (
	"context"
	"math/big"

	"github.com/pkg/errors"

	"github.com/ethereum/go-ethereum/core/types"

	"github.com/offchainlabs/arbitrum/packages/arb-node-core/ethbridge"
	"github.com/offchainlabs/arbitrum/packages/arb-node-core/ethutils"
	"github.com/offchainlabs/arbitrum/packages/arb-util/common"
	"github.com/offchainlabs/arbitrum/packages/arb-util/core"
	"github.com/offchainlabs/arbitrum/packages/arb-util/hashing"
)

type Validator struct {
	rollup         *ethbridge.Rollup
	bridge         *ethbridge.BridgeWatcher
	validatorUtils *ethbridge.ValidatorUtils
	client         ethutils.EthClient
	lookup         core.ArbCoreLookup
	builder        *ethbridge.BuilderBackend
	wallet         *ethbridge.ValidatorWallet
}

func NewValidator(
	ctx context.Context,
	lookup core.ArbCoreLookup,
	client ethutils.EthClient,
	wallet *ethbridge.ValidatorWallet,
	validatorUtilsAddress common.Address,
) (*Validator, error) {
	builder, err := ethbridge.NewBuilderBackend(wallet)
	if err != nil {
		return nil, err
	}
	rollup, err := ethbridge.NewRollup(wallet.RollupAddress().ToEthAddress(), client, builder)
	if err != nil {
		return nil, err
	}
	bridgeAddress, err := rollup.Bridge(ctx)
	if err != nil {
		return nil, err
	}
	bridge, err := ethbridge.NewBridgeWatcher(bridgeAddress.ToEthAddress(), client)
	if err != nil {
		return nil, err
	}
	validatorUtils, err := ethbridge.NewValidatorUtils(
		validatorUtilsAddress.ToEthAddress(),
		wallet.RollupAddress().ToEthAddress(),
		client,
	)
	if err != nil {
		return nil, err
	}
	return &Validator{
		rollup:         rollup,
		bridge:         bridge,
		validatorUtils: validatorUtils,
		client:         client,
		lookup:         lookup,
		builder:        builder,
		wallet:         wallet,
	}, nil
}

func (v *Validator) removeOldStakers(ctx context.Context) (*types.Transaction, error) {
	stakersToEliminate, err := v.validatorUtils.RefundableStakers(ctx)
	if err != nil {
		return nil, err
	}
	if len(stakersToEliminate) == 0 {
		return nil, nil
	}
	logger.Info().Int("count", len(stakersToEliminate)).Msg("Removing old stakers")
	return v.wallet.ReturnOldDeposits(ctx, stakersToEliminate)
}

func (v *Validator) resolveTimedOutChallenges(ctx context.Context) (*types.Transaction, error) {
	challengesToEliminate, err := v.validatorUtils.TimedOutChallenges(ctx, 1024)
	if err != nil {
		return nil, err
	}
	if len(challengesToEliminate) == 0 {
		return nil, nil
	}
	logger.Info().Int("count", len(challengesToEliminate)).Msg("Timing out challenges")
	return v.wallet.TimeoutChallenges(ctx, challengesToEliminate)
}

func (v *Validator) resolveNextNode(ctx context.Context) error {
	confirmType, successorWithStake, stakerAddress, err := v.validatorUtils.CheckDecidableNextNode(ctx)
	if err != nil {
		return err
	}
	switch confirmType {
	case ethbridge.CONFIRM_TYPE_INVALID:
		logger.Info().Msg("Rejecting node")
		return v.rollup.RejectNextNode(ctx, successorWithStake, stakerAddress)
	case ethbridge.CONFIRM_TYPE_VALID:
		unresolvedNodeIndex, err := v.rollup.FirstUnresolvedNode(ctx)
		if err != nil {
			return err
		}
		nodeInfo, err := v.rollup.RollupWatcher.LookupNode(ctx, unresolvedNodeIndex)
		if err != nil {
			return err
		}
		logAcc, err := v.lookup.GetLogAcc(common.Hash{}, nodeInfo.Assertion.Before.TotalLogCount, nodeInfo.Assertion.LogCount())
		if err != nil {
			return err
		}
		sends, err := v.lookup.GetSends(nodeInfo.Assertion.Before.TotalSendCount, nodeInfo.Assertion.SendCount())
		if err != nil {
			return err
		}
		logger.Info().Int("node", int(unresolvedNodeIndex.Int64())).Msg("Confirming node")
		return v.rollup.ConfirmNextNode(ctx, logAcc, sends)
	default:
		return nil
	}
}

type createNodeAction struct {
	assertion *core.Assertion
	hash      [32]byte
}

type existingNodeAction struct {
	number core.NodeID
	hash   [32]byte
}

type nodeAction interface{}

func (v *Validator) generateNodeAction(ctx context.Context, address common.Address, active bool, proactiveNewNodes bool) (nodeAction, bool, error) {
	base, baseHash, err := v.validatorUtils.LatestStaked(ctx, address)
	if err != nil {
		return nil, false, err
	}

	startState, err := lookupNodeStartState(ctx, v.rollup.RollupWatcher, base, baseHash)
	if err != nil {
		return nil, false, err
	}

	cursor, err := v.lookup.GetExecutionCursor(startState.TotalGasConsumed)
	if err != nil {
		return nil, false, err
	}
	if cursor.MachineHash() != startState.MachineHash {
		return nil, false, errors.New("local machine doesn't match chain")
	}

	// Not necessarily successors
	successorsNodes, err := v.rollup.LookupNodeChildren(ctx, baseHash)
	if err != nil {
		return nil, false, err
	}

	gasesUsed := make([]*big.Int, 0, len(successorsNodes)+1)
	gasesUsed = append(gasesUsed, startState.TotalGasConsumed)
	for _, nd := range successorsNodes {
		gasesUsed = append(gasesUsed, nd.Assertion.After.TotalGasConsumed)
	}

	currentBlock, err := getBlockID(ctx, v.client, nil)
	if err != nil {
		return nil, false, err
	}

	minAssertionPeriod, err := v.rollup.MinimumAssertionPeriod(ctx)
	if err != nil {
		return nil, false, err
	}

	timeSinceProposed := new(big.Int).Sub(currentBlock.Height.AsInt(), startState.ProposedBlock)
	if timeSinceProposed.Cmp(minAssertionPeriod) < 0 {
		// Too soon to assert
		return nil, false, nil
	}

	arbGasSpeedLimitPerBlock, err := v.rollup.ArbGasSpeedLimitPerBlock(ctx)
	if err != nil {
		return nil, false, err
	}

	minMessages := new(big.Int).Sub(startState.InboxMaxCount, startState.TotalMessagesRead)
	minimumGasToConsume := new(big.Int).Mul(timeSinceProposed, arbGasSpeedLimitPerBlock)
	maximumGasToConsume := new(big.Int).Mul(minimumGasToConsume, big.NewInt(4))

	if active {
		gasesUsed = append(gasesUsed, maximumGasToConsume)
	}

	execTracker := core.NewExecutionTracker(v.lookup, cursor, false, gasesUsed)

	var correctNode nodeAction
	wrongNodesExist := false
	for _, nd := range successorsNodes {
		if correctNode != nil && wrongNodesExist {
			// We've found everything we could hope to find
			break
		}
		if correctNode == nil {
			valid, err := core.IsAssertionValid(nd.Assertion, execTracker, nd.AfterInboxAcc)
			if err != nil {
				return nil, false, err
			}
			if valid {
				id := core.NodeID(nd.NodeNum)
				correctNode = existingNodeAction{
					number: id,
					hash:   nd.NodeHash,
				}
				continue
			}
		}
		// If we've hit this point, the node is "wrong"
		wrongNodesExist = true
	}

	if !active || correctNode != nil || (!proactiveNewNodes && !wrongNodesExist) {
		return correctNode, wrongNodesExist, nil
	}

	execInfo, _, err := execTracker.GetExecutionInfo(maximumGasToConsume)
	if err != nil {
		return nil, false, err
	}

	if execInfo.GasUsed().Cmp(minimumGasToConsume) < 0 && execInfo.InboxMessagesRead().Cmp(minMessages) < 0 {
		// Couldn't execute far enough
		return nil, wrongNodesExist, nil
	}

	inboxAcc := execInfo.After.InboxAcc
	hasSiblingByte := [1]byte{0}
	lastHash := baseHash
	if len(successorsNodes) > 0 {
		lastHash = successorsNodes[len(successorsNodes)-1].NodeHash
		hasSiblingByte[0] = 1
	}
	assertion := &core.Assertion{
		PrevProposedBlock: startState.ProposedBlock,
		PrevInboxMaxCount: startState.InboxMaxCount,
		ExecutionInfo:     execInfo,
	}
	executionHash := core.BisectionChunkHash(
		big.NewInt(0),
		execInfo.GasUsed(),
		assertion.BeforeExecutionHash(),
		assertion.AfterExecutionHash(),
	)
	newNodeHash := hashing.SoliditySHA3(hasSiblingByte[:], lastHash[:], executionHash[:], inboxAcc[:])
	action := createNodeAction{
		assertion: assertion,
		hash:      newNodeHash,
	}
	return action, wrongNodesExist, nil
}

func getBlockID(ctx context.Context, client ethutils.EthClient, number *big.Int) (*common.BlockId, error) {
	blockInfo, err := client.BlockInfoByNumber(ctx, number)
	if err != nil {
		return nil, err
	}
	return &common.BlockId{
		Height:     common.NewTimeBlocks((*big.Int)(blockInfo.Number)),
		HeaderHash: common.NewHashFromEth(blockInfo.Hash),
	}, nil
}

func lookupNodeStartState(ctx context.Context, rollup *ethbridge.RollupWatcher, nodeNum *big.Int, nodeHash [32]byte) (*core.NodeState, error) {
	if nodeNum.Cmp(big.NewInt(0)) == 0 {
		creationEvent, err := rollup.LookupCreation(ctx)
		if err != nil {
			return nil, err
		}
		return &core.NodeState{
			ProposedBlock: new(big.Int).SetUint64(creationEvent.Raw.BlockNumber),
			InboxMaxCount: big.NewInt(1),
			ExecutionState: &core.ExecutionState{
				TotalGasConsumed:  big.NewInt(0),
				MachineHash:       creationEvent.MachineHash,
				TotalMessagesRead: big.NewInt(0),
				TotalSendCount:    big.NewInt(0),
				TotalLogCount:     big.NewInt(0),
			},
		}, nil
	}
	node, err := rollup.LookupNode(ctx, nodeNum)
	if err != nil {
		return nil, err
	}
	if node.NodeHash != nodeHash {
		return nil, errors.New("Looked up starting node but found wrong hash")
	}
	return node.AfterState(), nil
}
