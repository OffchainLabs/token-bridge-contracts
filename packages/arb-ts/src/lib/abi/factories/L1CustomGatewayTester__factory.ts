/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Signer } from 'ethers'
import { Provider, TransactionRequest } from '@ethersproject/providers'
import { Contract, ContractFactory, Overrides } from '@ethersproject/contracts'

import type { L1CustomGatewayTester } from '../L1CustomGatewayTester'

export class L1CustomGatewayTester__factory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer)
  }

  deploy(overrides?: Overrides): Promise<L1CustomGatewayTester> {
    return super.deploy(overrides || {}) as Promise<L1CustomGatewayTester>
  }
  getDeployTransaction(overrides?: Overrides): TransactionRequest {
    return super.getDeployTransaction(overrides || {})
  }
  attach(address: string): L1CustomGatewayTester {
    return super.attach(address) as L1CustomGatewayTester
  }
  connect(signer: Signer): L1CustomGatewayTester__factory {
    return super.connect(signer) as L1CustomGatewayTester__factory
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): L1CustomGatewayTester {
    return new Contract(
      address,
      _abi,
      signerOrProvider
    ) as L1CustomGatewayTester
  }
}

const _abi = [
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: 'address',
        name: 'token',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'address',
        name: '_from',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'address',
        name: '_to',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'uint256',
        name: '_transferId',
        type: 'uint256',
      },
      {
        indexed: false,
        internalType: 'uint256',
        name: '_amount',
        type: 'uint256',
      },
      {
        indexed: false,
        internalType: 'bytes',
        name: '_data',
        type: 'bytes',
      },
    ],
    name: 'InboundTransferFinalized',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: 'address',
        name: 'token',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'address',
        name: '_from',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'address',
        name: '_to',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'uint256',
        name: '_transferId',
        type: 'uint256',
      },
      {
        indexed: false,
        internalType: 'uint256',
        name: '_amount',
        type: 'uint256',
      },
      {
        indexed: false,
        internalType: 'bytes',
        name: '_data',
        type: 'bytes',
      },
    ],
    name: 'OutboundTransferInitiated',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: 'address',
        name: 'l1Address',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'address',
        name: 'l2Address',
        type: 'address',
      },
    ],
    name: 'TokenSet',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: 'bool',
        name: 'success',
        type: 'bool',
      },
      {
        indexed: true,
        internalType: 'address',
        name: '_from',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'address',
        name: '_to',
        type: 'address',
      },
      {
        indexed: false,
        internalType: 'uint256',
        name: '_amount',
        type: 'uint256',
      },
      {
        indexed: false,
        internalType: 'bytes',
        name: 'callHookData',
        type: 'bytes',
      },
    ],
    name: 'TransferAndCallTriggered',
    type: 'event',
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: 'address',
        name: '_from',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'address',
        name: '_to',
        type: 'address',
      },
      {
        indexed: true,
        internalType: 'uint256',
        name: '_seqNum',
        type: 'uint256',
      },
      {
        indexed: false,
        internalType: 'bytes',
        name: '_data',
        type: 'bytes',
      },
    ],
    name: 'TxToL2',
    type: 'event',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'l1ERC20',
        type: 'address',
      },
    ],
    name: 'calculateL2TokenAddress',
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
    inputs: [],
    name: 'counterpartGateway',
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
        internalType: 'address',
        name: '_token',
        type: 'address',
      },
      {
        internalType: 'address',
        name: '_from',
        type: 'address',
      },
      {
        internalType: 'address',
        name: '_to',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: '_amount',
        type: 'uint256',
      },
      {
        internalType: 'bytes',
        name: '_data',
        type: 'bytes',
      },
    ],
    name: 'finalizeInboundTransfer',
    outputs: [
      {
        internalType: 'bytes',
        name: '',
        type: 'bytes',
      },
    ],
    stateMutability: 'payable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: '_token',
        type: 'address',
      },
      {
        internalType: 'address',
        name: '_from',
        type: 'address',
      },
      {
        internalType: 'address',
        name: '_to',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: '_amount',
        type: 'uint256',
      },
      {
        internalType: 'bytes',
        name: '_data',
        type: 'bytes',
      },
    ],
    name: 'getOutboundCalldata',
    outputs: [
      {
        internalType: 'bytes',
        name: 'outboundCalldata',
        type: 'bytes',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'inbox',
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
        internalType: 'address',
        name: '_l1Counterpart',
        type: 'address',
      },
      {
        internalType: 'address',
        name: '_l1Router',
        type: 'address',
      },
      {
        internalType: 'address',
        name: '_inbox',
        type: 'address',
      },
    ],
    name: 'initialize',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: '',
        type: 'address',
      },
    ],
    name: 'l1ToL2Token',
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
        internalType: 'address',
        name: '_l1Token',
        type: 'address',
      },
      {
        internalType: 'address',
        name: '_to',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: '_amount',
        type: 'uint256',
      },
      {
        internalType: 'uint256',
        name: '_maxGas',
        type: 'uint256',
      },
      {
        internalType: 'uint256',
        name: '_gasPriceBid',
        type: 'uint256',
      },
      {
        internalType: 'bytes',
        name: '_data',
        type: 'bytes',
      },
    ],
    name: 'outboundTransfer',
    outputs: [
      {
        internalType: 'bytes',
        name: 'res',
        type: 'bytes',
      },
    ],
    stateMutability: 'payable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'l2Address',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: '_maxGas',
        type: 'uint256',
      },
      {
        internalType: 'uint256',
        name: '_gasPriceBid',
        type: 'uint256',
      },
      {
        internalType: 'uint256',
        name: '_maxSubmissionCost',
        type: 'uint256',
      },
    ],
    name: 'registerTokenToL2',
    outputs: [
      {
        internalType: 'uint256',
        name: '',
        type: 'uint256',
      },
    ],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'router',
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
]

const _bytecode =
  '0x608060405234801561001057600080fd5b5061147a806100206000396000f3fe6080604052600436106100915760003560e01c8063c0c53b8b11610059578063c0c53b8b14610311578063d2ce7d6514610358578063f26bdead146103f2578063f887ea4014610449578063fb0e722b1461045e57610091565b80632db09c1c146100965780632e567b36146100c75780638a2dc014146101d2578063a0c76a9614610205578063a7e28d48146102de575b600080fd5b3480156100a257600080fd5b506100ab610473565b604080516001600160a01b039092168252519081900360200190f35b61015d600480360360a08110156100dd57600080fd5b6001600160a01b03823581169260208101358216926040820135909216916060820135919081019060a081016080820135600160201b81111561011f57600080fd5b82018360208201111561013157600080fd5b803590602001918460018302840111600160201b8311171561015257600080fd5b509092509050610482565b6040805160208082528351818301528351919283929083019185019080838360005b8381101561019757818101518382015260200161017f565b50505050905090810190601f1680156101c45780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b3480156101de57600080fd5b506100ab600480360360208110156101f557600080fd5b50356001600160a01b0316610642565b34801561021157600080fd5b5061015d600480360360a081101561022857600080fd5b6001600160a01b03823581169260208101358216926040820135909216916060820135919081019060a081016080820135600160201b81111561026a57600080fd5b82018360208201111561027c57600080fd5b803590602001918460018302840111600160201b8311171561029d57600080fd5b91908080601f01602080910402602001604051908101604052809392919081815260200183838082843760009201919091525092955061065d945050505050565b3480156102ea57600080fd5b506100ab6004803603602081101561030157600080fd5b50356001600160a01b0316610845565b34801561031d57600080fd5b506103566004803603606081101561033457600080fd5b506001600160a01b03813581169160208101358216916040909101351661089d565b005b61015d600480360360c081101561036e57600080fd5b6001600160a01b0382358116926020810135909116916040820135916060810135916080820135919081019060c0810160a0820135600160201b8111156103b457600080fd5b8201836020820111156103c657600080fd5b803590602001918460018302840111600160201b831117156103e757600080fd5b5090925090506108ad565b3480156103fe57600080fd5b506104376004803603608081101561041557600080fd5b506001600160a01b038135169060208101359060408101359060600135610a84565b60408051918252519081900360200190f35b34801561045557600080fd5b506100ab610b55565b34801561046a57600080fd5b506100ab610b64565b6000546001600160a01b031681565b606061048c610b73565b6104d8576040805162461bcd60e51b81526020600482015260186024820152774f4e4c595f434f554e544552504152545f4741544557415960401b604482015290519081900360640190fd5b60006060848460408110156104ec57600080fd5b81359190810190604081016020820135600160201b81111561050d57600080fd5b82018360208201111561051f57600080fd5b803590602001918460018302840111600160201b8311171561054057600080fd5b91908080601f01602080910402602001604051908101604052809392919081815260200183838082843760009201919091525096985091965061058f95508e94508c93508b9250610b84915050565b81876001600160a01b0316896001600160a01b03167f179a84706122b1b806f7d61c28c5caef276b7ff474ae596df3cad4bbaf0eb97d8c8a8a8a60405180856001600160a01b03166001600160a01b03168152602001848152602001806020018281038252848482818152602001925080828437600083820152604051601f909101601f191690920182900397509095505050505050a45050604080516020810190915260008152979650505050505050565b6003602052600090815260409020546001600160a01b031681565b606080604051806020016040528060008152509050632e567b3660e01b878787878588604051602001808060200180602001838103835285818151815260200191508051906020019080838360005b838110156106c45781810151838201526020016106ac565b50505050905090810190601f1680156106f15780820380516001836020036101000a031916815260200191505b50838103825284518152845160209182019186019080838360005b8381101561072457818101518382015260200161070c565b50505050905090810190601f1680156107515780820380516001836020036101000a031916815260200191505b5060408051601f19818403018152908290526001600160a01b03808c16602484019081528b82166044850152908a1660648401526084830189905260a060a48401908152825160c48501528251929850909650945060e4909101925060208601915080838360005b838110156107d15781810151838201526020016107b9565b50505050905090810190601f1680156107fe5780820380516001836020036101000a031916815260200191505b5060408051601f198184030181529190526020810180516001600160e01b03166001600160e01b0319909a1699909917909852509597505050505050505095945050505050565b600061084f610b9e565b61088e576040805162461bcd60e51b815260206004820152600b60248201526a27a7262cafa927aaaa22a960a91b604482015290519081900360640190fd5b61089782610baf565b92915050565b6108a8838383610bcd565b505050565b60606108b7610b9e565b6108f6576040805162461bcd60e51b815260206004820152600b60248201526a27a7262cafa927aaaa22a960a91b604482015290519081900360640190fd5b6000806000606061093c87878080601f016020809104026020016040519081016040528093929190818152602001838380828437600092019190915250610c9592505050565b919550925090506109556001600160a01b038d16610e5a565b610998576040805162461bcd60e51b815260206004820152600f60248201526e130c57d393d517d0d3d395149050d5608a1b604482015290519081900360640190fd5b60006109a38d610baf565b90506109b08d868d610e60565b6109c08d868e8e8e8e8989610e7b565b935050505080896001600160a01b0316836001600160a01b03167f9c003a9d1163eca79021710dcd5d9f657218bf2bd67aaa13389009a6047894a88d8c8a8a60405180856001600160a01b03166001600160a01b03168152602001848152602001806020018281038252848482818152602001925080828437600083820152604051601f909101601f191690920182900397509095505050505050a46040805160208082019390935281518082039093018352810190529998505050505050505050565b6000610a8f33610e5a565b610ad3576040805162461bcd60e51b815260206004820152601060248201526f135554d517d09157d0d3d395149050d560821b604482015290519081900360640190fd5b33600081815260036020908152604080832080546001600160a01b038b166001600160a01b031990911681179091558151602481018690526044808201929092528251808203909201825260640190915290810180516001600160e01b0316630e8dde7360e01b17905291610b4b9185888886610ea5565b9695505050505050565b6001546001600160a01b031681565b6002546001600160a01b031681565b6000546001600160a01b0316331490565b6108a86001600160a01b038416838363ffffffff610fac16565b6001546001600160a01b0316331490565b6001600160a01b039081166000908152600360205260409020541690565b6001600160a01b038216610c15576040805162461bcd60e51b815260206004820152600a6024820152692120a22fa927aaaa22a960b11b604482015290519081900360640190fd5b610c1f8383610ffe565b6001600160a01b038116610c66576040805162461bcd60e51b81526020600482015260096024820152680848288be929c849eb60bb1b604482015290519081900360640190fd5b600180546001600160a01b039384166001600160a01b0319918216179091556002805492909316911617905550565b6000806060610ca2610b9e565b15610d7d57838060200190516040811015610cbc57600080fd5b815160208301805160405192949293830192919084600160201b821115610ce257600080fd5b908301906020820185811115610cf757600080fd5b8251600160201b811182820188101715610d1057600080fd5b82525081516020918201929091019080838360005b83811015610d3d578181015183820152602001610d25565b50505050905090810190601f168015610d6a5780820380516001836020036101000a031916815260200191505b5060405250929550909250610d83915050565b50339150825b808060200190516040811015610d9857600080fd5b815160208301805160405192949293830192919084600160201b821115610dbe57600080fd5b908301906020820185811115610dd357600080fd5b8251600160201b811182820188101715610dec57600080fd5b82525081516020918201929091019080838360005b83811015610e19578181015183820152602001610e01565b50505050905090810190601f168015610e465780820380516001836020036101000a031916815260200191505b506040525095979296509094509092505050565b3b151590565b6108a86001600160a01b03841683308463ffffffff6110ca16565b6000610e98886000858888610e938f8f8f8f8c61065d565b610ea5565b9998505050505050505050565b60008054604051835183926060926001600160a01b0390911691869190819060208401908083835b60208310610eec5780518252601f199092019160209182019101610ecd565b6001836020036101000a0380198251168184511680821785525050505050509050019150506000604051808303816000865af19150503d8060008114610f4e576040519150601f19603f3d011682016040523d82523d6000602084013e610f53565b606091505b509150915081610f9c576040805162461bcd60e51b815260206004820152600f60248201526e13d5551093d5539117d49155915495608a1b604482015290519081900360640190fd5b5061053998975050505050505050565b604080516001600160a01b038416602482015260448082018490528251808303909101815260649091019091526020810180516001600160e01b031663a9059cbb60e01b1790526108a890849061112a565b6001600160a01b03821661104f576040805162461bcd60e51b81526020600482015260136024820152721253959053125117d0d3d55395115494105495606a1b604482015290519081900360640190fd5b6000546001600160a01b03161561109c576040805162461bcd60e51b815260206004820152600c60248201526b1053149150511657d253925560a21b604482015290519081900360640190fd5b600080546001600160a01b039384166001600160a01b03199182161790915560018054929093169116179055565b604080516001600160a01b0380861660248301528416604482015260648082018490528251808303909101815260849091019091526020810180516001600160e01b03166323b872dd60e01b17905261112490859061112a565b50505050565b606061117f826040518060400160405280602081526020017f5361666545524332303a206c6f772d6c6576656c2063616c6c206661696c6564815250856001600160a01b03166111db9092919063ffffffff16565b8051909150156108a85780806020019051602081101561119e57600080fd5b50516108a85760405162461bcd60e51b815260040180806020018281038252602a81526020018061141b602a913960400191505060405180910390fd5b60606111ea84846000856111f4565b90505b9392505050565b6060824710156112355760405162461bcd60e51b81526004018080602001828103825260268152602001806113f56026913960400191505060405180910390fd5b61123e85610e5a565b61128f576040805162461bcd60e51b815260206004820152601d60248201527f416464726573733a2063616c6c20746f206e6f6e2d636f6e7472616374000000604482015290519081900360640190fd5b60006060866001600160a01b031685876040518082805190602001908083835b602083106112ce5780518252601f1990920191602091820191016112af565b6001836020036101000a03801982511681845116808217855250505050505090500191505060006040518083038185875af1925050503d8060008114611330576040519150601f19603f3d011682016040523d82523d6000602084013e611335565b606091505b5091509150611345828286611350565b979650505050505050565b6060831561135f5750816111ed565b82511561136f5782518084602001fd5b8160405162461bcd60e51b81526004018080602001828103825283818151815260200191508051906020019080838360005b838110156113b95781810151838201526020016113a1565b50505050905090810190601f1680156113e65780820380516001836020036101000a031916815260200191505b509250505060405180910390fdfe416464726573733a20696e73756666696369656e742062616c616e636520666f722063616c6c5361666545524332303a204552433230206f7065726174696f6e20646964206e6f742073756363656564a2646970667358221220cfef1b13cc202d99043c464226003bc8be2755a082e6c57ab7f0ea0e109370ea64736f6c634300060b0033'
