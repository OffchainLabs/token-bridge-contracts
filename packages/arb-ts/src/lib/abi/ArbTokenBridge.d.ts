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
} from 'ethers'
import {
  Contract,
  ContractTransaction,
  Overrides,
  CallOverrides,
} from '@ethersproject/contracts'
import { BytesLike } from '@ethersproject/bytes'
import { Listener, Provider } from '@ethersproject/providers'
import { FunctionFragment, EventFragment, Result } from '@ethersproject/abi'

interface ArbTokenBridgeInterface extends ethers.utils.Interface {
  functions: {
    'calculateBridgedERC20Address(address)': FunctionFragment
    'calculateBridgedERC777Address(address)': FunctionFragment
    'customToken(address)': FunctionFragment
    'customTokenRegistered(address,address)': FunctionFragment
    'l1Pair()': FunctionFragment
    'migrate(address,address,address,uint256,bytes)': FunctionFragment
    'mintAndCall(address,uint256,address,address,bytes)': FunctionFragment
    'mintCustomTokenFromL1(address,address,uint256,bytes)': FunctionFragment
    'mintERC20FromL1(address,address,address,uint256,uint8,bytes)': FunctionFragment
    'mintERC777FromL1(address,address,address,uint256,uint8,bytes)': FunctionFragment
    'templateERC20()': FunctionFragment
    'templateERC777()': FunctionFragment
    'updateERC20TokenInfo(address,string,string,uint8)': FunctionFragment
    'updateERC777TokenInfo(address,string,string,uint8)': FunctionFragment
    'withdraw(address,address,uint256)': FunctionFragment
  }

  encodeFunctionData(
    functionFragment: 'calculateBridgedERC20Address',
    values: [string]
  ): string
  encodeFunctionData(
    functionFragment: 'calculateBridgedERC777Address',
    values: [string]
  ): string
  encodeFunctionData(functionFragment: 'customToken', values: [string]): string
  encodeFunctionData(
    functionFragment: 'customTokenRegistered',
    values: [string, string]
  ): string
  encodeFunctionData(functionFragment: 'l1Pair', values?: undefined): string
  encodeFunctionData(
    functionFragment: 'migrate',
    values: [string, string, string, BigNumberish, BytesLike]
  ): string
  encodeFunctionData(
    functionFragment: 'mintAndCall',
    values: [string, BigNumberish, string, string, BytesLike]
  ): string
  encodeFunctionData(
    functionFragment: 'mintCustomTokenFromL1',
    values: [string, string, BigNumberish, BytesLike]
  ): string
  encodeFunctionData(
    functionFragment: 'mintERC20FromL1',
    values: [string, string, string, BigNumberish, BigNumberish, BytesLike]
  ): string
  encodeFunctionData(
    functionFragment: 'mintERC777FromL1',
    values: [string, string, string, BigNumberish, BigNumberish, BytesLike]
  ): string
  encodeFunctionData(
    functionFragment: 'templateERC20',
    values?: undefined
  ): string
  encodeFunctionData(
    functionFragment: 'templateERC777',
    values?: undefined
  ): string
  encodeFunctionData(
    functionFragment: 'updateERC20TokenInfo',
    values: [string, string, string, BigNumberish]
  ): string
  encodeFunctionData(
    functionFragment: 'updateERC777TokenInfo',
    values: [string, string, string, BigNumberish]
  ): string
  encodeFunctionData(
    functionFragment: 'withdraw',
    values: [string, string, BigNumberish]
  ): string

  decodeFunctionResult(
    functionFragment: 'calculateBridgedERC20Address',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'calculateBridgedERC777Address',
    data: BytesLike
  ): Result
  decodeFunctionResult(functionFragment: 'customToken', data: BytesLike): Result
  decodeFunctionResult(
    functionFragment: 'customTokenRegistered',
    data: BytesLike
  ): Result
  decodeFunctionResult(functionFragment: 'l1Pair', data: BytesLike): Result
  decodeFunctionResult(functionFragment: 'migrate', data: BytesLike): Result
  decodeFunctionResult(functionFragment: 'mintAndCall', data: BytesLike): Result
  decodeFunctionResult(
    functionFragment: 'mintCustomTokenFromL1',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'mintERC20FromL1',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'mintERC777FromL1',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'templateERC20',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'templateERC777',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'updateERC20TokenInfo',
    data: BytesLike
  ): Result
  decodeFunctionResult(
    functionFragment: 'updateERC777TokenInfo',
    data: BytesLike
  ): Result
  decodeFunctionResult(functionFragment: 'withdraw', data: BytesLike): Result

  events: {
    'MintAndCallTriggered(bool)': EventFragment
  }

  getEvent(nameOrSignatureOrTopic: 'MintAndCallTriggered'): EventFragment
}

export class ArbTokenBridge extends Contract {
  connect(signerOrProvider: Signer | Provider | string): this
  attach(addressOrName: string): this
  deployed(): Promise<this>

  on(event: EventFilter | string, listener: Listener): this
  once(event: EventFilter | string, listener: Listener): this
  addListener(eventName: EventFilter | string, listener: Listener): this
  removeAllListeners(eventName: EventFilter | string): this
  removeListener(eventName: any, listener: Listener): this

  interface: ArbTokenBridgeInterface

  functions: {
    calculateBridgedERC20Address(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<[string]>

    'calculateBridgedERC20Address(address)'(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<[string]>

    calculateBridgedERC777Address(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<[string]>

    'calculateBridgedERC777Address(address)'(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<[string]>

    customToken(arg0: string, overrides?: CallOverrides): Promise<[string]>

    'customToken(address)'(
      arg0: string,
      overrides?: CallOverrides
    ): Promise<[string]>

    customTokenRegistered(
      l1Address: string,
      l2Address: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    'customTokenRegistered(address,address)'(
      l1Address: string,
      l2Address: string,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    l1Pair(overrides?: CallOverrides): Promise<[string]>

    'l1Pair()'(overrides?: CallOverrides): Promise<[string]>

    migrate(
      l1ERC20: string,
      target: string,
      account: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    'migrate(address,address,address,uint256,bytes)'(
      l1ERC20: string,
      target: string,
      account: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    mintAndCall(
      token: string,
      amount: BigNumberish,
      sender: string,
      dest: string,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    'mintAndCall(address,uint256,address,address,bytes)'(
      token: string,
      amount: BigNumberish,
      sender: string,
      dest: string,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    mintCustomTokenFromL1(
      l1ERC20: string,
      account: string,
      amount: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    'mintCustomTokenFromL1(address,address,uint256,bytes)'(
      l1ERC20: string,
      account: string,
      amount: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    mintERC20FromL1(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    'mintERC20FromL1(address,address,address,uint256,uint8,bytes)'(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    mintERC777FromL1(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    'mintERC777FromL1(address,address,address,uint256,uint8,bytes)'(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    templateERC20(overrides?: CallOverrides): Promise<[string]>

    'templateERC20()'(overrides?: CallOverrides): Promise<[string]>

    templateERC777(overrides?: CallOverrides): Promise<[string]>

    'templateERC777()'(overrides?: CallOverrides): Promise<[string]>

    updateERC20TokenInfo(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    'updateERC20TokenInfo(address,string,string,uint8)'(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    updateERC777TokenInfo(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    'updateERC777TokenInfo(address,string,string,uint8)'(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    withdraw(
      l1ERC20: string,
      destination: string,
      amount: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>

    'withdraw(address,address,uint256)'(
      l1ERC20: string,
      destination: string,
      amount: BigNumberish,
      overrides?: Overrides
    ): Promise<ContractTransaction>
  }

  calculateBridgedERC20Address(
    l1ERC20: string,
    overrides?: CallOverrides
  ): Promise<string>

  'calculateBridgedERC20Address(address)'(
    l1ERC20: string,
    overrides?: CallOverrides
  ): Promise<string>

  calculateBridgedERC777Address(
    l1ERC20: string,
    overrides?: CallOverrides
  ): Promise<string>

  'calculateBridgedERC777Address(address)'(
    l1ERC20: string,
    overrides?: CallOverrides
  ): Promise<string>

  customToken(arg0: string, overrides?: CallOverrides): Promise<string>

  'customToken(address)'(
    arg0: string,
    overrides?: CallOverrides
  ): Promise<string>

  customTokenRegistered(
    l1Address: string,
    l2Address: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  'customTokenRegistered(address,address)'(
    l1Address: string,
    l2Address: string,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  l1Pair(overrides?: CallOverrides): Promise<string>

  'l1Pair()'(overrides?: CallOverrides): Promise<string>

  migrate(
    l1ERC20: string,
    target: string,
    account: string,
    amount: BigNumberish,
    data: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  'migrate(address,address,address,uint256,bytes)'(
    l1ERC20: string,
    target: string,
    account: string,
    amount: BigNumberish,
    data: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  mintAndCall(
    token: string,
    amount: BigNumberish,
    sender: string,
    dest: string,
    data: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  'mintAndCall(address,uint256,address,address,bytes)'(
    token: string,
    amount: BigNumberish,
    sender: string,
    dest: string,
    data: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  mintCustomTokenFromL1(
    l1ERC20: string,
    account: string,
    amount: BigNumberish,
    callHookData: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  'mintCustomTokenFromL1(address,address,uint256,bytes)'(
    l1ERC20: string,
    account: string,
    amount: BigNumberish,
    callHookData: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  mintERC20FromL1(
    l1ERC20: string,
    sender: string,
    dest: string,
    amount: BigNumberish,
    decimals: BigNumberish,
    callHookData: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  'mintERC20FromL1(address,address,address,uint256,uint8,bytes)'(
    l1ERC20: string,
    sender: string,
    dest: string,
    amount: BigNumberish,
    decimals: BigNumberish,
    callHookData: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  mintERC777FromL1(
    l1ERC20: string,
    sender: string,
    dest: string,
    amount: BigNumberish,
    decimals: BigNumberish,
    callHookData: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  'mintERC777FromL1(address,address,address,uint256,uint8,bytes)'(
    l1ERC20: string,
    sender: string,
    dest: string,
    amount: BigNumberish,
    decimals: BigNumberish,
    callHookData: BytesLike,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  templateERC20(overrides?: CallOverrides): Promise<string>

  'templateERC20()'(overrides?: CallOverrides): Promise<string>

  templateERC777(overrides?: CallOverrides): Promise<string>

  'templateERC777()'(overrides?: CallOverrides): Promise<string>

  updateERC20TokenInfo(
    l1ERC20: string,
    name: string,
    symbol: string,
    decimals: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  'updateERC20TokenInfo(address,string,string,uint8)'(
    l1ERC20: string,
    name: string,
    symbol: string,
    decimals: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  updateERC777TokenInfo(
    l1ERC20: string,
    name: string,
    symbol: string,
    decimals: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  'updateERC777TokenInfo(address,string,string,uint8)'(
    l1ERC20: string,
    name: string,
    symbol: string,
    decimals: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  withdraw(
    l1ERC20: string,
    destination: string,
    amount: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  'withdraw(address,address,uint256)'(
    l1ERC20: string,
    destination: string,
    amount: BigNumberish,
    overrides?: Overrides
  ): Promise<ContractTransaction>

  callStatic: {
    calculateBridgedERC20Address(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<string>

    'calculateBridgedERC20Address(address)'(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<string>

    calculateBridgedERC777Address(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<string>

    'calculateBridgedERC777Address(address)'(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<string>

    customToken(arg0: string, overrides?: CallOverrides): Promise<string>

    'customToken(address)'(
      arg0: string,
      overrides?: CallOverrides
    ): Promise<string>

    customTokenRegistered(
      l1Address: string,
      l2Address: string,
      overrides?: CallOverrides
    ): Promise<void>

    'customTokenRegistered(address,address)'(
      l1Address: string,
      l2Address: string,
      overrides?: CallOverrides
    ): Promise<void>

    l1Pair(overrides?: CallOverrides): Promise<string>

    'l1Pair()'(overrides?: CallOverrides): Promise<string>

    migrate(
      l1ERC20: string,
      target: string,
      account: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    'migrate(address,address,address,uint256,bytes)'(
      l1ERC20: string,
      target: string,
      account: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    mintAndCall(
      token: string,
      amount: BigNumberish,
      sender: string,
      dest: string,
      data: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    'mintAndCall(address,uint256,address,address,bytes)'(
      token: string,
      amount: BigNumberish,
      sender: string,
      dest: string,
      data: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    mintCustomTokenFromL1(
      l1ERC20: string,
      account: string,
      amount: BigNumberish,
      callHookData: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    'mintCustomTokenFromL1(address,address,uint256,bytes)'(
      l1ERC20: string,
      account: string,
      amount: BigNumberish,
      callHookData: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    mintERC20FromL1(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    'mintERC20FromL1(address,address,address,uint256,uint8,bytes)'(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    mintERC777FromL1(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    'mintERC777FromL1(address,address,address,uint256,uint8,bytes)'(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: CallOverrides
    ): Promise<void>

    templateERC20(overrides?: CallOverrides): Promise<string>

    'templateERC20()'(overrides?: CallOverrides): Promise<string>

    templateERC777(overrides?: CallOverrides): Promise<string>

    'templateERC777()'(overrides?: CallOverrides): Promise<string>

    updateERC20TokenInfo(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>

    'updateERC20TokenInfo(address,string,string,uint8)'(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>

    updateERC777TokenInfo(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>

    'updateERC777TokenInfo(address,string,string,uint8)'(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>

    withdraw(
      l1ERC20: string,
      destination: string,
      amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>

    'withdraw(address,address,uint256)'(
      l1ERC20: string,
      destination: string,
      amount: BigNumberish,
      overrides?: CallOverrides
    ): Promise<void>
  }

  filters: {
    MintAndCallTriggered(success: null): EventFilter
  }

  estimateGas: {
    calculateBridgedERC20Address(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>

    'calculateBridgedERC20Address(address)'(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>

    calculateBridgedERC777Address(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>

    'calculateBridgedERC777Address(address)'(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>

    customToken(arg0: string, overrides?: CallOverrides): Promise<BigNumber>

    'customToken(address)'(
      arg0: string,
      overrides?: CallOverrides
    ): Promise<BigNumber>

    customTokenRegistered(
      l1Address: string,
      l2Address: string,
      overrides?: Overrides
    ): Promise<BigNumber>

    'customTokenRegistered(address,address)'(
      l1Address: string,
      l2Address: string,
      overrides?: Overrides
    ): Promise<BigNumber>

    l1Pair(overrides?: CallOverrides): Promise<BigNumber>

    'l1Pair()'(overrides?: CallOverrides): Promise<BigNumber>

    migrate(
      l1ERC20: string,
      target: string,
      account: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    'migrate(address,address,address,uint256,bytes)'(
      l1ERC20: string,
      target: string,
      account: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    mintAndCall(
      token: string,
      amount: BigNumberish,
      sender: string,
      dest: string,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    'mintAndCall(address,uint256,address,address,bytes)'(
      token: string,
      amount: BigNumberish,
      sender: string,
      dest: string,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    mintCustomTokenFromL1(
      l1ERC20: string,
      account: string,
      amount: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    'mintCustomTokenFromL1(address,address,uint256,bytes)'(
      l1ERC20: string,
      account: string,
      amount: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    mintERC20FromL1(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    'mintERC20FromL1(address,address,address,uint256,uint8,bytes)'(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    mintERC777FromL1(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    'mintERC777FromL1(address,address,address,uint256,uint8,bytes)'(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<BigNumber>

    templateERC20(overrides?: CallOverrides): Promise<BigNumber>

    'templateERC20()'(overrides?: CallOverrides): Promise<BigNumber>

    templateERC777(overrides?: CallOverrides): Promise<BigNumber>

    'templateERC777()'(overrides?: CallOverrides): Promise<BigNumber>

    updateERC20TokenInfo(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>

    'updateERC20TokenInfo(address,string,string,uint8)'(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>

    updateERC777TokenInfo(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>

    'updateERC777TokenInfo(address,string,string,uint8)'(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>

    withdraw(
      l1ERC20: string,
      destination: string,
      amount: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>

    'withdraw(address,address,uint256)'(
      l1ERC20: string,
      destination: string,
      amount: BigNumberish,
      overrides?: Overrides
    ): Promise<BigNumber>
  }

  populateTransaction: {
    calculateBridgedERC20Address(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>

    'calculateBridgedERC20Address(address)'(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>

    calculateBridgedERC777Address(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>

    'calculateBridgedERC777Address(address)'(
      l1ERC20: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>

    customToken(
      arg0: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>

    'customToken(address)'(
      arg0: string,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>

    customTokenRegistered(
      l1Address: string,
      l2Address: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    'customTokenRegistered(address,address)'(
      l1Address: string,
      l2Address: string,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    l1Pair(overrides?: CallOverrides): Promise<PopulatedTransaction>

    'l1Pair()'(overrides?: CallOverrides): Promise<PopulatedTransaction>

    migrate(
      l1ERC20: string,
      target: string,
      account: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    'migrate(address,address,address,uint256,bytes)'(
      l1ERC20: string,
      target: string,
      account: string,
      amount: BigNumberish,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    mintAndCall(
      token: string,
      amount: BigNumberish,
      sender: string,
      dest: string,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    'mintAndCall(address,uint256,address,address,bytes)'(
      token: string,
      amount: BigNumberish,
      sender: string,
      dest: string,
      data: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    mintCustomTokenFromL1(
      l1ERC20: string,
      account: string,
      amount: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    'mintCustomTokenFromL1(address,address,uint256,bytes)'(
      l1ERC20: string,
      account: string,
      amount: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    mintERC20FromL1(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    'mintERC20FromL1(address,address,address,uint256,uint8,bytes)'(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    mintERC777FromL1(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    'mintERC777FromL1(address,address,address,uint256,uint8,bytes)'(
      l1ERC20: string,
      sender: string,
      dest: string,
      amount: BigNumberish,
      decimals: BigNumberish,
      callHookData: BytesLike,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    templateERC20(overrides?: CallOverrides): Promise<PopulatedTransaction>

    'templateERC20()'(overrides?: CallOverrides): Promise<PopulatedTransaction>

    templateERC777(overrides?: CallOverrides): Promise<PopulatedTransaction>

    'templateERC777()'(overrides?: CallOverrides): Promise<PopulatedTransaction>

    updateERC20TokenInfo(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    'updateERC20TokenInfo(address,string,string,uint8)'(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    updateERC777TokenInfo(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    'updateERC777TokenInfo(address,string,string,uint8)'(
      l1ERC20: string,
      name: string,
      symbol: string,
      decimals: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    withdraw(
      l1ERC20: string,
      destination: string,
      amount: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>

    'withdraw(address,address,uint256)'(
      l1ERC20: string,
      destination: string,
      amount: BigNumberish,
      overrides?: Overrides
    ): Promise<PopulatedTransaction>
  }
}
