/* Generated by ts-generator ver. 0.0.8 */
/* tslint:disable */

import { Contract, ContractTransaction, EventFilter, Signer } from 'ethers';
import { Listener, Provider } from 'ethers/providers';
import { Arrayish, BigNumber, BigNumberish, Interface } from 'ethers/utils';
import { TransactionOverrides, TypedEventDescription, TypedFunctionDescription } from '.';

interface ArbRollupInterface extends Interface {
    functions: {
        pruneLeaf: TypedFunctionDescription<{
            encode([from, leafProof, latestConfirmedProof]: [Arrayish, (Arrayish)[], (Arrayish)[]]): string;
        }>;

        resolveChallenge: TypedFunctionDescription<{
            encode([winner, loser]: [string, string]): string;
        }>;

        startChallenge: TypedFunctionDescription<{
            encode([
                asserterAddress,
                challengerAddress,
                prevNode,
                deadlineTicks,
                stakerNodeTypes,
                vmProtoHashes,
                asserterProof,
                challengerProof,
                asserterNodeHash,
                challengerDataHash,
                challengerPeriodTicks,
            ]: [
                string,
                string,
                Arrayish,
                BigNumberish,
                (BigNumberish)[],
                (Arrayish)[],
                (Arrayish)[],
                (Arrayish)[],
                Arrayish,
                Arrayish,
                BigNumberish,
            ]): string;
        }>;

        init: TypedFunctionDescription<{
            encode([
                _vmState,
                _gracePeriodTicks,
                _arbGasSpeedLimitPerTick,
                _maxExecutionSteps,
                _stakeRequirement,
                _owner,
                _challengeFactoryAddress,
                _globalInboxAddress,
            ]: [Arrayish, BigNumberish, BigNumberish, BigNumberish, BigNumberish, string, string, string]): string;
        }>;

        placeStake: TypedFunctionDescription<{
            encode([proof1, proof2]: [(Arrayish)[], (Arrayish)[]]): string;
        }>;

        moveStake: TypedFunctionDescription<{
            encode([proof1, proof2]: [(Arrayish)[], (Arrayish)[]]): string;
        }>;

        recoverStakeConfirmed: TypedFunctionDescription<{
            encode([proof]: [(Arrayish)[]]): string;
        }>;

        recoverStakeOld: TypedFunctionDescription<{
            encode([stakerAddress, proof]: [string, (Arrayish)[]]): string;
        }>;

        recoverStakeMooted: TypedFunctionDescription<{
            encode([stakerAddress, node, latestConfirmedProof, stakerProof]: [
                string,
                Arrayish,
                (Arrayish)[],
                (Arrayish)[],
            ]): string;
        }>;

        recoverStakePassedDeadline: TypedFunctionDescription<{
            encode([stakerAddress, deadlineTicks, disputableNodeHashVal, childType, vmProtoStateHash, proof]: [
                string,
                BigNumberish,
                Arrayish,
                BigNumberish,
                Arrayish,
                (Arrayish)[],
            ]): string;
        }>;

        makeAssertion: TypedFunctionDescription<{
            encode([
                _fields,
                _beforePendingCount,
                _prevDeadlineTicks,
                _prevChildType,
                _numSteps,
                _timeBoundsBlocks,
                _importedMessageCount,
                _didInboxInsn,
                _numArbGas,
                _stakerProof,
            ]: [
                (Arrayish)[],
                BigNumberish,
                BigNumberish,
                BigNumberish,
                BigNumberish,
                (BigNumberish)[],
                BigNumberish,
                boolean,
                BigNumberish,
                (Arrayish)[],
            ]): string;
        }>;

        confirmValid: TypedFunctionDescription<{
            encode([
                deadlineTicks,
                _messages,
                logsAcc,
                vmProtoStateHash,
                stakerAddresses,
                stakerProofs,
                stakerProofOffsets,
            ]: [BigNumberish, Arrayish, Arrayish, Arrayish, (string)[], (Arrayish)[], (BigNumberish)[]]): string;
        }>;

        confirmInvalid: TypedFunctionDescription<{
            encode([
                deadlineTicks,
                challengeNodeData,
                branch,
                vmProtoStateHash,
                stakerAddresses,
                stakerProofs,
                stakerProofOffsets,
            ]: [BigNumberish, Arrayish, BigNumberish, Arrayish, (string)[], (Arrayish)[], (BigNumberish)[]]): string;
        }>;
    };

    events: {
        ConfirmedAssertion: TypedEventDescription<{
            encodeTopics([logsAccHash]: [null]): string[];
        }>;

        RollupAsserted: TypedEventDescription<{
            encodeTopics([
                fields,
                pendingCount,
                importedMessageCount,
                timeBoundsBlocks,
                numArbGas,
                numSteps,
                didInboxInsn,
            ]: [null, null, null, null, null, null, null]): string[];
        }>;

        RollupChallengeCompleted: TypedEventDescription<{
            encodeTopics([challengeContract, winner, loser]: [null, null, null]): string[];
        }>;

        RollupChallengeStarted: TypedEventDescription<{
            encodeTopics([asserter, challenger, challengeType, challengeContract]: [null, null, null, null]): string[];
        }>;

        RollupConfirmed: TypedEventDescription<{
            encodeTopics([nodeHash]: [null]): string[];
        }>;

        RollupCreated: TypedEventDescription<{
            encodeTopics([initVMHash]: [null]): string[];
        }>;

        RollupPruned: TypedEventDescription<{
            encodeTopics([leaf]: [null]): string[];
        }>;

        RollupStakeCreated: TypedEventDescription<{
            encodeTopics([staker, nodeHash]: [null, null]): string[];
        }>;

        RollupStakeMoved: TypedEventDescription<{
            encodeTopics([staker, toNodeHash]: [null, null]): string[];
        }>;

        RollupStakeRefunded: TypedEventDescription<{
            encodeTopics([staker]: [null]): string[];
        }>;
    };
}

export class ArbRollup extends Contract {
    connect(signerOrProvider: Signer | Provider | string): ArbRollup;
    attach(addressOrName: string): ArbRollup;
    deployed(): Promise<ArbRollup>;

    on(event: EventFilter | string, listener: Listener): ArbRollup;
    once(event: EventFilter | string, listener: Listener): ArbRollup;
    addListener(eventName: EventFilter | string, listener: Listener): ArbRollup;
    removeAllListeners(eventName: EventFilter | string): ArbRollup;
    removeListener(eventName: any, listener: Listener): ArbRollup;

    interface: ArbRollupInterface;

    functions: {
        isStaked(_stakerAddress: string): Promise<boolean>;

        isValidLeaf(leaf: Arrayish): Promise<boolean>;

        vmParams(): Promise<{
            gracePeriodTicks: BigNumber;
            arbGasSpeedLimitPerTick: BigNumber;
            maxExecutionSteps: number;
            0: BigNumber;
            1: BigNumber;
            2: number;
        }>;

        pruneLeaf(
            from: Arrayish,
            leafProof: (Arrayish)[],
            latestConfirmedProof: (Arrayish)[],
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        resolveChallenge(winner: string, loser: string, overrides?: TransactionOverrides): Promise<ContractTransaction>;

        startChallenge(
            asserterAddress: string,
            challengerAddress: string,
            prevNode: Arrayish,
            deadlineTicks: BigNumberish,
            stakerNodeTypes: (BigNumberish)[],
            vmProtoHashes: (Arrayish)[],
            asserterProof: (Arrayish)[],
            challengerProof: (Arrayish)[],
            asserterNodeHash: Arrayish,
            challengerDataHash: Arrayish,
            challengerPeriodTicks: BigNumberish,
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        init(
            _vmState: Arrayish,
            _gracePeriodTicks: BigNumberish,
            _arbGasSpeedLimitPerTick: BigNumberish,
            _maxExecutionSteps: BigNumberish,
            _stakeRequirement: BigNumberish,
            _owner: string,
            _challengeFactoryAddress: string,
            _globalInboxAddress: string,
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        placeStake(
            proof1: (Arrayish)[],
            proof2: (Arrayish)[],
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        moveStake(
            proof1: (Arrayish)[],
            proof2: (Arrayish)[],
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        recoverStakeConfirmed(proof: (Arrayish)[], overrides?: TransactionOverrides): Promise<ContractTransaction>;

        recoverStakeOld(
            stakerAddress: string,
            proof: (Arrayish)[],
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        recoverStakeMooted(
            stakerAddress: string,
            node: Arrayish,
            latestConfirmedProof: (Arrayish)[],
            stakerProof: (Arrayish)[],
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        recoverStakePassedDeadline(
            stakerAddress: string,
            deadlineTicks: BigNumberish,
            disputableNodeHashVal: Arrayish,
            childType: BigNumberish,
            vmProtoStateHash: Arrayish,
            proof: (Arrayish)[],
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        makeAssertion(
            _fields: (Arrayish)[],
            _beforePendingCount: BigNumberish,
            _prevDeadlineTicks: BigNumberish,
            _prevChildType: BigNumberish,
            _numSteps: BigNumberish,
            _timeBoundsBlocks: (BigNumberish)[],
            _importedMessageCount: BigNumberish,
            _didInboxInsn: boolean,
            _numArbGas: BigNumberish,
            _stakerProof: (Arrayish)[],
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        confirmValid(
            deadlineTicks: BigNumberish,
            _messages: Arrayish,
            logsAcc: Arrayish,
            vmProtoStateHash: Arrayish,
            stakerAddresses: (string)[],
            stakerProofs: (Arrayish)[],
            stakerProofOffsets: (BigNumberish)[],
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        confirmInvalid(
            deadlineTicks: BigNumberish,
            challengeNodeData: Arrayish,
            branch: BigNumberish,
            vmProtoStateHash: Arrayish,
            stakerAddresses: (string)[],
            stakerProofs: (Arrayish)[],
            stakerProofOffsets: (BigNumberish)[],
            overrides?: TransactionOverrides,
        ): Promise<ContractTransaction>;

        challengeFactory(): Promise<string>;
        getStakeRequired(): Promise<BigNumber>;
        globalInbox(): Promise<string>;
        latestConfirmed(): Promise<string>;
    };

    filters: {
        ConfirmedAssertion(logsAccHash: null): EventFilter;

        RollupAsserted(
            fields: null,
            pendingCount: null,
            importedMessageCount: null,
            timeBoundsBlocks: null,
            numArbGas: null,
            numSteps: null,
            didInboxInsn: null,
        ): EventFilter;

        RollupChallengeCompleted(challengeContract: null, winner: null, loser: null): EventFilter;

        RollupChallengeStarted(
            asserter: null,
            challenger: null,
            challengeType: null,
            challengeContract: null,
        ): EventFilter;

        RollupConfirmed(nodeHash: null): EventFilter;

        RollupCreated(initVMHash: null): EventFilter;

        RollupPruned(leaf: null): EventFilter;

        RollupStakeCreated(staker: null, nodeHash: null): EventFilter;

        RollupStakeMoved(staker: null, toNodeHash: null): EventFilter;

        RollupStakeRefunded(staker: null): EventFilter;
    };

    estimate: {
        pruneLeaf(from: Arrayish, leafProof: (Arrayish)[], latestConfirmedProof: (Arrayish)[]): Promise<BigNumber>;

        resolveChallenge(winner: string, loser: string): Promise<BigNumber>;

        startChallenge(
            asserterAddress: string,
            challengerAddress: string,
            prevNode: Arrayish,
            deadlineTicks: BigNumberish,
            stakerNodeTypes: (BigNumberish)[],
            vmProtoHashes: (Arrayish)[],
            asserterProof: (Arrayish)[],
            challengerProof: (Arrayish)[],
            asserterNodeHash: Arrayish,
            challengerDataHash: Arrayish,
            challengerPeriodTicks: BigNumberish,
        ): Promise<BigNumber>;

        init(
            _vmState: Arrayish,
            _gracePeriodTicks: BigNumberish,
            _arbGasSpeedLimitPerTick: BigNumberish,
            _maxExecutionSteps: BigNumberish,
            _stakeRequirement: BigNumberish,
            _owner: string,
            _challengeFactoryAddress: string,
            _globalInboxAddress: string,
        ): Promise<BigNumber>;

        placeStake(proof1: (Arrayish)[], proof2: (Arrayish)[]): Promise<BigNumber>;

        moveStake(proof1: (Arrayish)[], proof2: (Arrayish)[]): Promise<BigNumber>;

        recoverStakeConfirmed(proof: (Arrayish)[]): Promise<BigNumber>;

        recoverStakeOld(stakerAddress: string, proof: (Arrayish)[]): Promise<BigNumber>;

        recoverStakeMooted(
            stakerAddress: string,
            node: Arrayish,
            latestConfirmedProof: (Arrayish)[],
            stakerProof: (Arrayish)[],
        ): Promise<BigNumber>;

        recoverStakePassedDeadline(
            stakerAddress: string,
            deadlineTicks: BigNumberish,
            disputableNodeHashVal: Arrayish,
            childType: BigNumberish,
            vmProtoStateHash: Arrayish,
            proof: (Arrayish)[],
        ): Promise<BigNumber>;

        makeAssertion(
            _fields: (Arrayish)[],
            _beforePendingCount: BigNumberish,
            _prevDeadlineTicks: BigNumberish,
            _prevChildType: BigNumberish,
            _numSteps: BigNumberish,
            _timeBoundsBlocks: (BigNumberish)[],
            _importedMessageCount: BigNumberish,
            _didInboxInsn: boolean,
            _numArbGas: BigNumberish,
            _stakerProof: (Arrayish)[],
        ): Promise<BigNumber>;

        confirmValid(
            deadlineTicks: BigNumberish,
            _messages: Arrayish,
            logsAcc: Arrayish,
            vmProtoStateHash: Arrayish,
            stakerAddresses: (string)[],
            stakerProofs: (Arrayish)[],
            stakerProofOffsets: (BigNumberish)[],
        ): Promise<BigNumber>;

        confirmInvalid(
            deadlineTicks: BigNumberish,
            challengeNodeData: Arrayish,
            branch: BigNumberish,
            vmProtoStateHash: Arrayish,
            stakerAddresses: (string)[],
            stakerProofs: (Arrayish)[],
            stakerProofOffsets: (BigNumberish)[],
        ): Promise<BigNumber>;
    };
}
