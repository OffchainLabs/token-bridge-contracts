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

interface IExitLiquidityProviderInterface extends ethers.utils.Interface {
  functions: {
    'requestLiquidity(address,address,uint256,uint256,bytes)': FunctionFragment
  }

  encodeFunctionData(
    functionFragment: 'requestLiquidity',
    values: [string, string, BigNumberish, BigNumberish, BytesLike]
  ): string

  decodeFunctionResult(
    functionFragment: 'requestLiquidity',
    data: BytesLike
  ): Result

  events: {}
}

export class IExitLiquidityProvider extends BaseContract {
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

  interface: IExitLiquidityProviderInterface

  functions: {
    requestLiquidity(
      dest: string,
      erc20: string,
      amount: BigNumberish,
      exitNum: BigNumberish,
      liquidityProof: BytesLike,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>
  }

  requestLiquidity(
    dest: string,
    erc20: string,
    amount: BigNumberish,
    exitNum: BigNumberish,
    liquidityProof: BytesLike,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>

  callStatic: {
    requestLiquidity(
      dest: string,
      erc20: string,
      amount: BigNumberish,
      exitNum: BigNumberish,
      liquidityProof: BytesLike,
      overrides?: CallOverrides
    ): Promise<string>
  }

  filters: {}

  estimateGas: {
    requestLiquidity(
      dest: string,
      erc20: string,
      amount: BigNumberish,
      exitNum: BigNumberish,
      liquidityProof: BytesLike,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<BigNumber>
  }

  populateTransaction: {
    requestLiquidity(
      dest: string,
      erc20: string,
      amount: BigNumberish,
      exitNum: BigNumberish,
      liquidityProof: BytesLike,
      overrides?: Overrides & { from?: string | Promise<string> }
    ): Promise<PopulatedTransaction>
  }
}
