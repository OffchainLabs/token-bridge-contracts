/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Signer } from 'ethers'
import { Provider, TransactionRequest } from '@ethersproject/providers'
import { Contract, ContractFactory, Overrides } from '@ethersproject/contracts'

import type { StandardArbERC20 } from '../StandardArbERC20'

export class StandardArbERC20__factory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer)
  }

  deploy(overrides?: Overrides): Promise<StandardArbERC20> {
    return super.deploy(overrides || {}) as Promise<StandardArbERC20>
  }
  getDeployTransaction(overrides?: Overrides): TransactionRequest {
    return super.getDeployTransaction(overrides || {})
  }
  attach(address: string): StandardArbERC20 {
    return super.attach(address) as StandardArbERC20
  }
  connect(signer: Signer): StandardArbERC20__factory {
    return super.connect(signer) as StandardArbERC20__factory
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): StandardArbERC20 {
    return new Contract(address, _abi, signerOrProvider) as StandardArbERC20
  }
}

const _abi = [
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: 'address',
        name: 'owner',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'address',
        name: 'spender',
        type: 'address',
      },
      {
        indexed: false,
        internalType: 'uint256',
        name: 'value',
        type: 'uint256',
      },
    ],
    name: 'Approval',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: 'address',
        name: 'from',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'address',
        name: 'to',
        type: 'address',
      },
      {
        indexed: false,
        internalType: 'uint256',
        name: 'value',
        type: 'uint256',
      },
    ],
    name: 'Transfer',
    type: 'event',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'owner',
        type: 'address',
      },
      {
        internalType: 'address',
        name: 'spender',
        type: 'address',
      },
    ],
    name: 'allowance',
    outputs: [
      {
        internalType: 'uint256',
        name: '',
        type: 'uint256',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'spender',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: 'amount',
        type: 'uint256',
      },
    ],
    name: 'approve',
    outputs: [
      {
        internalType: 'bool',
        name: '',
        type: 'bool',
      },
    ],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'account',
        type: 'address',
      },
    ],
    name: 'balanceOf',
    outputs: [
      {
        internalType: 'uint256',
        name: '',
        type: 'uint256',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'bridge',
    outputs: [
      {
        internalType: 'contract ArbTokenBridge',
        name: '',
        type: 'address',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'account',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: 'amount',
        type: 'uint256',
      },
      {
        internalType: 'bytes',
        name: 'data',
        type: 'bytes',
      },
    ],
    name: 'bridgeMint',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'decimals',
    outputs: [
      {
        internalType: 'uint8',
        name: '',
        type: 'uint8',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'spender',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: 'subtractedValue',
        type: 'uint256',
      },
    ],
    name: 'decreaseAllowance',
    outputs: [
      {
        internalType: 'bool',
        name: '',
        type: 'bool',
      },
    ],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'spender',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: 'addedValue',
        type: 'uint256',
      },
    ],
    name: 'increaseAllowance',
    outputs: [
      {
        internalType: 'bool',
        name: '',
        type: 'bool',
      },
    ],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: '_bridge',
        type: 'address',
      },
      {
        internalType: 'address',
        name: '_l1Address',
        type: 'address',
      },
      {
        internalType: 'uint8',
        name: 'decimals_',
        type: 'uint8',
      },
    ],
    name: 'initialize',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'isMaster',
    outputs: [
      {
        internalType: 'bool',
        name: '',
        type: 'bool',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'l1Address',
    outputs: [
      {
        internalType: 'address',
        name: '',
        type: 'address',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'uint256',
        name: 'amount',
        type: 'uint256',
      },
      {
        internalType: 'address',
        name: 'target',
        type: 'address',
      },
      {
        internalType: 'bytes',
        name: 'data',
        type: 'bytes',
      },
    ],
    name: 'migrate',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'name',
    outputs: [
      {
        internalType: 'string',
        name: '',
        type: 'string',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'symbol',
    outputs: [
      {
        internalType: 'string',
        name: '',
        type: 'string',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'totalSupply',
    outputs: [
      {
        internalType: 'uint256',
        name: '',
        type: 'uint256',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'recipient',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: 'amount',
        type: 'uint256',
      },
    ],
    name: 'transfer',
    outputs: [
      {
        internalType: 'bool',
        name: '',
        type: 'bool',
      },
    ],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'sender',
        type: 'address',
      },
      {
        internalType: 'address',
        name: 'recipient',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: 'amount',
        type: 'uint256',
      },
    ],
    name: 'transferFrom',
    outputs: [
      {
        internalType: 'bool',
        name: '',
        type: 'bool',
      },
    ],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'string',
        name: 'newName',
        type: 'string',
      },
      {
        internalType: 'string',
        name: 'newSymbol',
        type: 'string',
      },
    ],
    name: 'updateInfo',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'destination',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: 'amount',
        type: 'uint256',
      },
    ],
    name: 'withdraw',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
]

const _bytecode =
  '0x608060405234801561001057600080fd5b506005805461ff0019166101001790556114278061002f6000396000f3fe608060405234801561001057600080fd5b50600436106101115760003560e01c806370a08231116100ad578063c2eeeebd11610071578063c2eeeebd14610519578063cb6eb3f41461053d578063dd62ed3e146105f6578063e78cea9214610624578063f3fef3a31461062c57610111565b806370a082311461045957806389232a001461047f57806395d89b41146104b9578063a457c2d7146104c1578063a9059cbb146104ed57610111565b806306fdde0314610116578063095ea7b31461019357806318160ddd146101d35780631fd192f7146101ed57806323b872dd146102a8578063313ce567146102de57806339509351146102fc57806347d5a091146103285780636f791d2914610451575b600080fd5b61011e610658565b6040805160208082528351818301528351919283929083019185019080838360005b83811015610158578181015183820152602001610140565b50505050905090810190601f1680156101855780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b6101bf600480360360408110156101a957600080fd5b506001600160a01b0381351690602001356106ef565b604080519115158252519081900360200190f35b6101db61070c565b60408051918252519081900360200190f35b6102a66004803603606081101561020357600080fd5b8135916001600160a01b0360208201351691810190606081016040820135600160201b81111561023257600080fd5b82018360208201111561024457600080fd5b803590602001918460018302840111600160201b8311171561026557600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250929550610712945050505050565b005b6101bf600480360360608110156102be57600080fd5b506001600160a01b0381358116916020810135909116906040013561081f565b6102e66108ac565b6040805160ff9092168252519081900360200190f35b6101bf6004803603604081101561031257600080fd5b506001600160a01b0381351690602001356108b5565b6102a66004803603604081101561033e57600080fd5b810190602081018135600160201b81111561035857600080fd5b82018360208201111561036a57600080fd5b803590602001918460018302840111600160201b8311171561038b57600080fd5b91908080601f0160208091040260200160405190810160405280939291908181526020018383808284376000920191909152509295949360208101935035915050600160201b8111156103dd57600080fd5b8201836020820111156103ef57600080fd5b803590602001918460018302840111600160201b8311171561041057600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250929550610909945050505050565b6101bf610998565b6101db6004803603602081101561046f57600080fd5b50356001600160a01b03166109a6565b6102a66004803603606081101561049557600080fd5b5080356001600160a01b03908116916020810135909116906040013560ff166109c1565b61011e610a5f565b6101bf600480360360408110156104d757600080fd5b506001600160a01b038135169060200135610ac0565b6101bf6004803603604081101561050357600080fd5b506001600160a01b038135169060200135610b2e565b610521610b42565b604080516001600160a01b039092168252519081900360200190f35b6102a66004803603606081101561055357600080fd5b6001600160a01b0382351691602081013591810190606081016040820135600160201b81111561058257600080fd5b82018360208201111561059457600080fd5b803590602001918460018302840111600160201b831117156105b557600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250929550610b51945050505050565b6101db6004803603604081101561060c57600080fd5b506001600160a01b0381358116916020013516610bae565b610521610bd9565b6102a66004803603604081101561064257600080fd5b506001600160a01b038135169060200135610bee565b60038054604080516020601f60026000196101006001881615020190951694909404938401819004810282018101909252828152606093909290918301828280156106e45780601f106106b9576101008083540402835291602001916106e4565b820191906000526020600020905b8154815290600101906020018083116106c757829003601f168201915b505050505090505b90565b60006107036106fc610c7b565b8484610c7f565b50600192915050565b60025490565b61071c3384610d6b565b60055460065460405163214c337360e11b81526001600160a01b0391821660048201818152868416602484015233604484018190526064840189905260a060848501908152875160a48601528751620100009097049095169563429866e6959394899492938b938a939192909160c490910190602085019080838360005b838110156107b257818101518382015260200161079a565b50505050905090810190601f1680156107df5780820380516001836020036101000a031916815260200191505b509650505050505050600060405180830381600087803b15801561080257600080fd5b505af1158015610816573d6000803e3d6000fd5b50505050505050565b600061082c848484610e61565b6108a284610838610c7b565b61089d8560405180606001604052806028815260200161131b602891396001600160a01b038a16600090815260016020526040812090610876610c7b565b6001600160a01b03168152602081019190915260400160002054919063ffffffff610fb616565b610c7f565b5060019392505050565b60055460ff1690565b60006107036108c2610c7b565b8461089d85600160006108d3610c7b565b6001600160a01b03908116825260208083019390935260409182016000908120918c16815292529020549063ffffffff61104d16565b6005546201000090046001600160a01b0316331461095c576040805162461bcd60e51b815260206004820152600b60248201526a4f4e4c595f42524944474560a81b604482015290519081900360640190fd5b8151156109785781516109769060039060208501906111f5565b505b8051156109945780516109929060049060208401906111f5565b505b5050565b600554610100900460ff1690565b6001600160a01b031660009081526020819052604090205490565b6005546201000090046001600160a01b031615610a14576040805162461bcd60e51b815260206004820152600c60248201526b1053149150511657d253925560a21b604482015290519081900360640190fd5b60058054600680546001600160a01b0319166001600160a01b0395861617905562010000600160b01b0319166201000094909316939093029190911760ff191660ff91909116179055565b60048054604080516020601f60026000196101006001881615020190951694909404938401819004810282018101909252828152606093909290918301828280156106e45780601f106106b9576101008083540402835291602001916106e4565b6000610703610acd610c7b565b8461089d856040518060600160405280602581526020016113cd6025913960016000610af7610c7b565b6001600160a01b03908116825260208083019390935260409182016000908120918d1681529252902054919063ffffffff610fb616565b6000610703610b3b610c7b565b8484610e61565b6006546001600160a01b031681565b6005546201000090046001600160a01b03163314610ba4576040805162461bcd60e51b815260206004820152600b60248201526a4f4e4c595f42524944474560a81b604482015290519081900360640190fd5b61099283836110ae565b6001600160a01b03918216600090815260016020908152604080832093909416825291909152205490565b6005546201000090046001600160a01b031681565b610bf83382610d6b565b60055460065460408051636ce5768960e11b81526001600160a01b0392831660048201528583166024820152604481018590529051620100009093049091169163d9caed129160648082019260009290919082900301818387803b158015610c5f57600080fd5b505af1158015610c73573d6000803e3d6000fd5b505050505050565b3390565b6001600160a01b038316610cc45760405162461bcd60e51b81526004018080602001828103825260248152602001806113a96024913960400191505060405180910390fd5b6001600160a01b038216610d095760405162461bcd60e51b81526004018080602001828103825260228152602001806112d36022913960400191505060405180910390fd5b6001600160a01b03808416600081815260016020908152604080832094871680845294825291829020859055815185815291517f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b9259281900390910190a3505050565b6001600160a01b038216610db05760405162461bcd60e51b81526004018080602001828103825260218152602001806113636021913960400191505060405180910390fd5b610dbc82600083610992565b610dff816040518060600160405280602281526020016112b1602291396001600160a01b038516600090815260208190526040902054919063ffffffff610fb616565b6001600160a01b038316600090815260208190526040902055600254610e2b908263ffffffff61119816565b6002556040805182815290516000916001600160a01b038516916000805160206113438339815191529181900360200190a35050565b6001600160a01b038316610ea65760405162461bcd60e51b81526004018080602001828103825260258152602001806113846025913960400191505060405180910390fd5b6001600160a01b038216610eeb5760405162461bcd60e51b815260040180806020018281038252602381526020018061128e6023913960400191505060405180910390fd5b610ef6838383610992565b610f39816040518060600160405280602681526020016112f5602691396001600160a01b038616600090815260208190526040902054919063ffffffff610fb616565b6001600160a01b038085166000908152602081905260408082209390935590841681522054610f6e908263ffffffff61104d16565b6001600160a01b0380841660008181526020818152604091829020949094558051858152905191939287169260008051602061134383398151915292918290030190a3505050565b600081848411156110455760405162461bcd60e51b81526004018080602001828103825283818151815260200191508051906020019080838360005b8381101561100a578181015183820152602001610ff2565b50505050905090810190601f1680156110375780820380516001836020036101000a031916815260200191505b509250505060405180910390fd5b505050900390565b6000828201838110156110a7576040805162461bcd60e51b815260206004820152601b60248201527f536166654d6174683a206164646974696f6e206f766572666c6f770000000000604482015290519081900360640190fd5b9392505050565b6001600160a01b038216611109576040805162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f206164647265737300604482015290519081900360640190fd5b61111560008383610992565b600254611128908263ffffffff61104d16565b6002556001600160a01b038216600090815260208190526040902054611154908263ffffffff61104d16565b6001600160a01b0383166000818152602081815260408083209490945583518581529351929391926000805160206113438339815191529281900390910190a35050565b6000828211156111ef576040805162461bcd60e51b815260206004820152601e60248201527f536166654d6174683a207375627472616374696f6e206f766572666c6f770000604482015290519081900360640190fd5b50900390565b828054600181600116156101000203166002900490600052602060002090601f016020900481019282601f1061123657805160ff1916838001178555611263565b82800160010185558215611263579182015b82811115611263578251825591602001919060010190611248565b5061126f929150611273565b5090565b6106ec91905b8082111561126f576000815560010161127956fe45524332303a207472616e7366657220746f20746865207a65726f206164647265737345524332303a206275726e20616d6f756e7420657863656564732062616c616e636545524332303a20617070726f766520746f20746865207a65726f206164647265737345524332303a207472616e7366657220616d6f756e7420657863656564732062616c616e636545524332303a207472616e7366657220616d6f756e74206578636565647320616c6c6f77616e6365ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef45524332303a206275726e2066726f6d20746865207a65726f206164647265737345524332303a207472616e736665722066726f6d20746865207a65726f206164647265737345524332303a20617070726f76652066726f6d20746865207a65726f206164647265737345524332303a2064656372656173656420616c6c6f77616e63652062656c6f77207a65726fa2646970667358221220eb7d2bd4effd374f74db2d6c7c19ff07279b68f6d3048860640ec4623ce19eb864736f6c634300060b0033'
