/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer, utils } from 'ethers'
import { Provider } from '@ethersproject/providers'
import type {
  IExitLiquidityProvider,
  IExitLiquidityProviderInterface,
} from '../IExitLiquidityProvider'

const _abi = [
  {
    inputs: [
      {
        internalType: 'address',
        name: 'dest',
        type: 'address',
      },
      {
        internalType: 'address',
        name: 'erc20',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: 'amount',
        type: 'uint256',
      },
      {
        internalType: 'uint256',
        name: 'exitNum',
        type: 'uint256',
      },
      {
        internalType: 'bytes',
        name: 'liquidityProof',
        type: 'bytes',
      },
    ],
    name: 'requestLiquidity',
    outputs: [
      {
        internalType: 'bytes',
        name: '',
        type: 'bytes',
      },
    ],
    stateMutability: 'nonpayable',
    type: 'function',
  },
]

export class IExitLiquidityProvider__factory {
  static readonly abi = _abi
  static createInterface(): IExitLiquidityProviderInterface {
    return new utils.Interface(_abi) as IExitLiquidityProviderInterface
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): IExitLiquidityProvider {
    return new Contract(
      address,
      _abi,
      signerOrProvider
    ) as IExitLiquidityProvider
  }
}
