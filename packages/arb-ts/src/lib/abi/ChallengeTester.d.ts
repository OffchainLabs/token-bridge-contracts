/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import {
  ethers,
  EventFilter,
  Signer,
  BigNumber,
  BigNumberish,
  PopulatedTransaction,
  BaseContract,
  ContractTransaction,
  Overrides,
  CallOverrides,
} from 'ethers'
import { BytesLike } from '@ethersproject/bytes'
import { Listener, Provider } from '@ethersproject/providers'
import { FunctionFragment, EventFragment, Result } from '@ethersproject/abi'
import { TypedEventFilter, TypedEvent, TypedListener } from './commons'

interface ChallengeTesterInterface extends ethers.utils.Interface {
  functions: {
    'challenge()': FunctionFragment
    'challengeCompleted()': FunctionFragment
    'challengeExecutionBisectionDegree()': FunctionFragment
    'challengeFactory()': FunctionFragment
    'completeChallenge(address,address)': FunctionFragment
    'loser()': FunctionFragment
    'startChallenge(bytes32,uint256,address,address,uint256,uint256,address,address)': FunctionFragment
    'winner()': FunctionFragment
  }

  encodeFunctionData(functionFragment: 'challenge', values?: undefined): string
  encodeFunctionData(
    functionFragment: 'challengeCompleted',
    values?: undefined
  ): string
  encodeFunctionData(
    functionFragment: 'challengeExecutionBisectionDegree',
    values?: undefined
  ): string
  encodeFunctionData(
    functionFragment: 'challengeFactory',
    values?: undefined
  ): string
  encodeFunctionData(
    functionFragment: 'completeChallenge',
    values: [string, string]
  ): string
  encodeFunctionData(functionFragment: 'loser', values?: undefined): string
  encodeFunctionData(
    functionFragment: 'startChallenge',
    values: [
      BytesLike,
      BigNumberish,
      string,
      string,
      BigNumberish,
      BigNumberish,
      string,
      string
    ]
  ): string
  encodeFunctionData(functionFragment: 'winner', values?: undefined): string

  decodeFunctionResult(functionFragment: 'challenge', data: BytesLike): Result
  decodeFunctionResult(
    functionFragment: 'challengeCompleted',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'challengeExecutionBisectionDegree',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'challengeFactory',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'completeChallenge',
    data: BytesLike
  ): Result
  decodeFunctionResult(functionFragment: 'loser', data: BytesLike): Result
  decodeFunctionResult(
    functionFragment: 'startChallenge',
    data: BytesLike
  ): Result
  decodeFunctionResult(functionFragment: 'winner', data: BytesLike): Result

  events: {}
}

export class ChallengeTester extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this
  attach(addressOrName: string): this
  deployed(): Promise<this>

  listeners<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter?: TypedEventFilter<EventArgsArray, EventArgsObject>
  ): Array<TypedListener<EventArgsArray, EventArgsObject>>
  off<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>,
    listener: TypedListener<EventArgsArray, EventArgsObject>
  ): this
  on<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>,
    listener: TypedListener<EventArgsArray, EventArgsObject>
  ): this
  once<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>,
    listener: TypedListener<EventArgsArray, EventArgsObject>
  ): this
  removeListener<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>,
    listener: TypedListener<EventArgsArray, EventArgsObject>
  ): this
  removeAllListeners<EventArgsArray extends Array<any>, EventArgsObject>(
    eventFilter: TypedEventFilter<EventArgsArray, EventArgsObject>
  ): this

  listeners(eventName?: string): Array<Listener>
  off(eventName: string, listener: Listener): this
  on(eventName: string, listener: Listener): this
  once(eventName: string, listener: Listener): this
  removeListener(eventName: string, listener: Listener): this
  removeAllListeners(eventName?: string): this

  queryFilter<EventArgsArray extends Array<any>, EventArgsObject>(
    event: TypedEventFilter<EventArgsArray, EventArgsObject>,
    fromBlockOrBlockhash?: string | number | undefined,
    toBlock?: string | number | undefined
  ): Promise<Array<TypedEvent<EventArgsArray & EventArgsObject>>>

  interface: ChallengeTesterInterface

  functions: {
    challenge(overrides?: CallOverrides): Promise<[string]>

    challengeCompleted(overrides?: CallOverrides): Promise<[boolean]>

    challengeExecutionBisectionDegree(
      overrides?: CallOverrides
    ): Promise<[BigNumber]>

    challengeFactory(overrides?: CallOverrides): Promise<[string]>

    completeChallenge(
      _winner: string,
      _loser: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>

    loser(overrides?: CallOverrides): Promise<[string]>

    startChallenge(
      executionHash: BytesLike,
      maxMessageCount: BigNumberish,
      asserter: string,
      challenger: string,
      asserterTimeLeft: BigNumberish,
      challengerTimeLeft: BigNumberish,
      sequencerBridge: string,
      delayedBridge: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>

    winner(overrides?: CallOverrides): Promise<[string]>
  }

  challenge(overrides?: CallOverrides): Promise<string>

  challengeCompleted(overrides?: CallOverrides): Promise<boolean>

  challengeExecutionBisectionDegree(
    overrides?: CallOverrides
  ): Promise<BigNumber>

  challengeFactory(overrides?: CallOverrides): Promise<string>

  completeChallenge(
    _winner: string,
    _loser: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>

  loser(overrides?: CallOverrides): Promise<string>

  startChallenge(
    executionHash: BytesLike,
    maxMessageCount: BigNumberish,
    asserter: string,
    challenger: string,
    asserterTimeLeft: BigNumberish,
    challengerTimeLeft: BigNumberish,
    sequencerBridge: string,
    delayedBridge: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>

  winner(overrides?: CallOverrides): Promise<string>

  callStatic: {
    challenge(overrides?: CallOverrides): Promise<string>

    challengeCompleted(overrides?: CallOverrides): Promise<boolean>

    challengeExecutionBisectionDegree(
      overrides?: CallOverrides
    ): Promise<BigNumber>

    challengeFactory(overrides?: CallOverrides): Promise<string>

    completeChallenge(
      _winner: string,
      _loser: string,
      overrides?: CallOverrides
    ): Promise<void>

    loser(overrides?: CallOverrides): Promise<string>

    startChallenge(
      executionHash: BytesLike,
      maxMessageCount: BigNumberish,
      asserter: string,
      challenger: string,
      asserterTimeLeft: BigNumberish,
      challengerTimeLeft: BigNumberish,
      sequencerBridge: string,
      delayedBridge: string,
      overrides?: CallOverrides
    ): Promise<void>

    winner(overrides?: CallOverrides): Promise<string>
  }

  filters: {}

  estimateGas: {
    challenge(overrides?: CallOverrides): Promise<BigNumber>

    challengeCompleted(overrides?: CallOverrides): Promise<BigNumber>

    challengeExecutionBisectionDegree(
      overrides?: CallOverrides
    ): Promise<BigNumber>

    challengeFactory(overrides?: CallOverrides): Promise<BigNumber>

    completeChallenge(
      _winner: string,
      _loser: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>

    loser(overrides?: CallOverrides): Promise<BigNumber>

    startChallenge(
      executionHash: BytesLike,
      maxMessageCount: BigNumberish,
      asserter: string,
      challenger: string,
      asserterTimeLeft: BigNumberish,
      challengerTimeLeft: BigNumberish,
      sequencerBridge: string,
      delayedBridge: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>

    winner(overrides?: CallOverrides): Promise<BigNumber>
  }

  populateTransaction: {
    challenge(overrides?: CallOverrides): Promise<PopulatedTransaction>

    challengeCompleted(overrides?: CallOverrides): Promise<PopulatedTransaction>

    challengeExecutionBisectionDegree(
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>

    challengeFactory(overrides?: CallOverrides): Promise<PopulatedTransaction>

    completeChallenge(
      _winner: string,
      _loser: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>

    loser(overrides?: CallOverrides): Promise<PopulatedTransaction>

    startChallenge(
      executionHash: BytesLike,
      maxMessageCount: BigNumberish,
      asserter: string,
      challenger: string,
      asserterTimeLeft: BigNumberish,
      challengerTimeLeft: BigNumberish,
      sequencerBridge: string,
      delayedBridge: string,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>

    winner(overrides?: CallOverrides): Promise<PopulatedTransaction>
  }
}
