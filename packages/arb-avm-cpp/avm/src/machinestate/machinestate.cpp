/*
 * Copyright 2019, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <avm/checkpoint/machinestatefetcher.hpp>
#include <avm/exceptions.hpp>
#include <avm/machinestate/machineoperation.hpp>
#include <avm/machinestate/machinestate.hpp>
#include <bigint_utils.hpp>
#include <util.hpp>

namespace {
std::vector<CodePoint> opsToCodePoints(const std::vector<Operation>& ops) {
    std::vector<CodePoint> cps;
    cps.reserve(ops.size());
    uint64_t pc = 0;
    for (auto& op : ops) {
        cps.emplace_back(pc, std::move(op), 0);
        pc++;
    }
    for (uint64_t i = 0; i < cps.size() - 1; i++) {
        cps[cps.size() - 2 - i].nextHash = hash(cps[cps.size() - 1 - i]);
    }
    return cps;
}
}  // namespace

void uint256_t_to_buf(const uint256_t& val, std::vector<unsigned char>& buf) {
    std::array<unsigned char, 32> tmpbuf;
    to_big_endian(val, tmpbuf.begin());
    buf.insert(buf.end(), tmpbuf.begin(), tmpbuf.end());
}

MachineState::MachineState()
    : pool(std::make_unique<TuplePool>()),
      pendingInbox(pool.get()),
      context({0, 0}),
      inbox(pool.get()) {}

uint256_t MachineState::hash() const {
    if (state == Status::Halted)
        return 0;
    if (state == Status::Error)
        return 1;

    std::array<unsigned char, 32 * 6> data;
    auto oit = data.begin();
    {
        auto val = ::hash(code[pc]);
        std::array<uint64_t, 4> hashInts;
        to_big_endian(val, hashInts.begin());
        std::copy(reinterpret_cast<unsigned char*>(hashInts.data()),
                  reinterpret_cast<unsigned char*>(hashInts.data()) + 32, oit);
        oit += 32;
    }
    {
        auto val = stack.hash();
        std::array<uint64_t, 4> hashInts;
        to_big_endian(val, hashInts.begin());
        std::copy(reinterpret_cast<unsigned char*>(hashInts.data()),
                  reinterpret_cast<unsigned char*>(hashInts.data()) + 32, oit);
        oit += 32;
    }
    {
        auto val = auxstack.hash();
        std::array<uint64_t, 4> hashInts;
        to_big_endian(val, hashInts.begin());
        std::copy(reinterpret_cast<unsigned char*>(hashInts.data()),
                  reinterpret_cast<unsigned char*>(hashInts.data()) + 32, oit);
        oit += 32;
    }
    {
        auto val = ::hash(registerVal);
        std::array<uint64_t, 4> hashInts;
        to_big_endian(val, hashInts.begin());
        std::copy(reinterpret_cast<unsigned char*>(hashInts.data()),
                  reinterpret_cast<unsigned char*>(hashInts.data()) + 32, oit);
        oit += 32;
    }
    {
        auto val = ::hash(staticVal);
        std::array<uint64_t, 4> hashInts;
        to_big_endian(val, hashInts.begin());
        std::copy(reinterpret_cast<unsigned char*>(hashInts.data()),
                  reinterpret_cast<unsigned char*>(hashInts.data()) + 32, oit);
        oit += 32;
    }
    {
        auto val = ::hash(errpc);
        std::array<uint64_t, 4> hashInts;
        to_big_endian(val, hashInts.begin());
        std::copy(reinterpret_cast<unsigned char*>(hashInts.data()),
                  reinterpret_cast<unsigned char*>(hashInts.data()) + 32, oit);
        oit += 32;
    }

    std::array<unsigned char, 32> hashData;
    evm::Keccak_256(data.data(), 32 * 6, hashData.data());
    return from_big_endian(hashData.begin(), hashData.end());
}

bool MachineState::deserialize(const char* bufptr) {
    uint32_t version;
    memcpy(&version, bufptr, sizeof(version));
    version = __builtin_bswap32(version);
    bufptr += sizeof(version);

    if (version != CURRENT_AO_VERSION) {
        std::cerr << "incorrect version of .ao file" << std::endl;
        std::cerr << "expected version " << CURRENT_AO_VERSION
                  << " found version " << version << std::endl;
        return false;
    }

    uint32_t extentionId = 1;
    while (extentionId != 0) {
        memcpy(&extentionId, bufptr, sizeof(extentionId));
        extentionId = __builtin_bswap32(extentionId);
        bufptr += sizeof(extentionId);
        if (extentionId > 0) {
            //            std::cout << "found extention" << std::endl;
        }
    }
    uint64_t codeCount;
    memcpy(&codeCount, bufptr, sizeof(codeCount));
    bufptr += sizeof(codeCount);
    codeCount = boost::endian::big_to_native(codeCount);
    code.reserve(codeCount);

    std::vector<Operation> ops;
    for (uint64_t i = 0; i < codeCount; i++) {
        ops.emplace_back(deserializeOperation(bufptr, *pool));
    }
    code = opsToCodePoints(ops);

    staticVal = deserialize_value(bufptr, *pool);
    pc = 0;
    return true;
}

uint64_t MachineState::pendingMessageCount() const {
    return pendingInbox.messageCount;
}

void MachineState::sendOnchainMessage(const Message& msg) {
    pendingInbox.addMessage(msg);
    balance.add(msg.token, msg.currency);
}

void MachineState::sendOffchainMessages(const std::vector<Message>& messages) {
    MessageStack messageStack(pool.get());
    for (const auto& message : messages) {
        messageStack.addMessage(message);
    }
    inbox.addMessageStack(std::move(messageStack));
}

void MachineState::deliverOnchainMessages() {
    inbox.addMessageStack(std::move(pendingInbox));
    pendingInbox.clear();
}

void MachineState::setInbox(MessageStack ms) {
    inbox = ms;
}

void MachineState::setPendingInbox(MessageStack ms) {
    pendingInbox = ms;
}

std::vector<unsigned char> MachineState::marshalForProof() {
    std::vector<unsigned char> buf;
    auto opcode = code[pc].op.opcode;
    std::vector<bool> stackPops = InstructionStackPops.at(opcode);
    bool includeImmediateVal = false;
    if (code[pc].op.immediate && !stackPops.empty()) {
        includeImmediateVal = stackPops[0] == true;
        stackPops.erase(stackPops.begin());
    }
    std::vector<bool> auxStackPops = InstructionAuxStackPops.at(opcode);
    auto stackProof = stack.marshalForProof(stackPops);
    auto auxStackProof = auxstack.marshalForProof(auxStackPops);
    uint256_t_to_buf(code[pc].nextHash, buf);
    uint256_t_to_buf(stackProof.first, buf);
    uint256_t_to_buf(auxStackProof.first, buf);
    uint256_t_to_buf(::hash(registerVal), buf);
    uint256_t_to_buf(::hash(staticVal), buf);
    uint256_t_to_buf(::hash(errpc), buf);
    code[pc].op.marshalForProof(buf, includeImmediateVal);

    buf.insert(buf.end(), stackProof.second.begin(), stackProof.second.end());
    buf.insert(buf.end(), auxStackProof.second.begin(),
               auxStackProof.second.end());
    return buf;
}

SaveResults MachineState::checkpointState(CheckpointStorage& storage) {
    auto stateSaver = MachineStateSaver(storage.makeTransaction());

    auto datastack_results = stack.checkpointState(stateSaver, pool.get());
    auto auxstack_results = auxstack.checkpointState(stateSaver, pool.get());
    auto inbox_results = inbox.checkpointState(stateSaver);
    auto pending_results = pendingInbox.checkpointState(stateSaver);

    auto static_val_results = stateSaver.saveValue(staticVal);
    auto register_val_results = stateSaver.saveValue(registerVal);
    auto err_code_point = stateSaver.saveValue(errpc);
    auto pc_results = stateSaver.saveValue(code[pc]);

    auto status_str = static_cast<unsigned char>(state);
    auto blockreason_str = serializeForCheckpoint(blockReason);
    auto balancetracker_str = balance.serializeBalanceValues();

    auto hash_key = GetHashKey(hash());

    if (datastack_results.status.ok() && auxstack_results.status.ok() &&
        inbox_results.msgs_tuple_results.status.ok() &&
        inbox_results.msg_count_results.status.ok() &&
        pending_results.msgs_tuple_results.status.ok() &&
        pending_results.msg_count_results.status.ok() &&
        static_val_results.status.ok() && register_val_results.status.ok() &&
        pc_results.status.ok() && err_code_point.status.ok()) {
        auto machine_state_data = ParsedState{
            static_val_results.storage_key,
            register_val_results.storage_key,
            datastack_results.storage_key,
            auxstack_results.storage_key,
            inbox_results.msgs_tuple_results.storage_key,
            inbox_results.msg_count_results.storage_key,
            pending_results.msgs_tuple_results.storage_key,
            pending_results.msg_count_results.storage_key,
            pc_results.storage_key,
            err_code_point.storage_key,
            status_str,
            blockreason_str,
            balancetracker_str,
        };

        auto results =
            stateSaver.saveMachineState(machine_state_data, hash_key);
        results.status = stateSaver.commitTransaction();
        return results;
    } else {
        return SaveResults{0, rocksdb::Status().Aborted(), hash_key};
    }
}

DbResult<ParsedState> MachineState::restoreCheckpoint(
    const CheckpointStorage& storage,
    const std::vector<unsigned char>& checkpoint_key) {
    auto stateFetcher = MachineStateFetcher(storage, pool.get(), code);
    auto results = stateFetcher.getMachineState(checkpoint_key);

    if (results.status.ok()) {
        auto state_data = results.data;

        auto static_val_results =
            stateFetcher.getValue(state_data.static_val_key);
        staticVal = static_val_results.data;

        auto register_results =
            stateFetcher.getValue(state_data.register_val_key);
        registerVal = register_results.data;

        auto pc_results = stateFetcher.getCodePoint(state_data.pc_key);
        pc = pc_results.data.pc;

        auto err_pc_results = stateFetcher.getCodePoint(state_data.err_pc_key);
        errpc = err_pc_results.data;

        stack.initializeDataStack(stateFetcher, state_data.datastack_key);
        auxstack.initializeDataStack(stateFetcher, state_data.auxstack_key);

        inbox.initializeMessageStack(stateFetcher, state_data.inbox_key,
                                     state_data.inbox_count_key);

        pendingInbox.initializeMessageStack(
            stateFetcher, state_data.pending_key, state_data.pending_count_key);

        state = static_cast<Status>(state_data.status_char);
        blockReason = deserializeBlockReason(state_data.blockreason_str);
        balance = BalanceTracker(state_data.balancetracker_str);
    }

    return results;
}

BlockReason MachineState::runOp(OpCode opcode) {
    switch (opcode) {
            /**************************/
            /*  Arithmetic Operations */
            /**************************/
        case OpCode::ADD:
            MachineOperation::add(*this);
            break;
        case OpCode::MUL:
            MachineOperation::mul(*this);
            break;
        case OpCode::SUB:
            MachineOperation::sub(*this);
            break;
        case OpCode::DIV:
            MachineOperation::div(*this);
            break;
        case OpCode::SDIV:
            MachineOperation::sdiv(*this);
            break;
        case OpCode::MOD:
            MachineOperation::mod(*this);
            break;
        case OpCode::SMOD:
            MachineOperation::smod(*this);
            break;
        case OpCode::ADDMOD:
            MachineOperation::addmod(*this);
            break;
        case OpCode::MULMOD:
            MachineOperation::mulmod(*this);
            break;
        case OpCode::EXP:
            MachineOperation::exp(*this);
            break;
            /******************************************/
            /*  Comparison & Bitwise Logic Operations */
            /******************************************/
        case OpCode::LT:
            MachineOperation::lt(*this);
            break;
        case OpCode::GT:
            MachineOperation::gt(*this);
            break;
        case OpCode::SLT:
            MachineOperation::slt(*this);
            break;
        case OpCode::SGT:
            MachineOperation::sgt(*this);
            break;
        case OpCode::EQ:
            MachineOperation::eq(*this);
            break;
        case OpCode::ISZERO:
            MachineOperation::iszero(*this);
            break;
        case OpCode::BITWISE_AND:
            MachineOperation::bitwiseAnd(*this);
            break;
        case OpCode::BITWISE_OR:
            MachineOperation::bitwiseOr(*this);
            break;
        case OpCode::BITWISE_XOR:
            MachineOperation::bitwiseXor(*this);
            break;
        case OpCode::BITWISE_NOT:
            MachineOperation::bitwiseNot(*this);
            break;
        case OpCode::BYTE:
            MachineOperation::byte(*this);
            break;
        case OpCode::SIGNEXTEND:
            MachineOperation::signExtend(*this);
            break;

            /***********************/
            /*  Hashing Operations */
            /***********************/
        case OpCode::HASH:
            MachineOperation::hashOp(*this);
            break;

        case OpCode::TYPE:
            MachineOperation::typeOp(*this);
            break;

            /***********************************************/
            /*  Stack, Memory, Storage and Flow Operations */
            /***********************************************/
        case OpCode::POP:
            MachineOperation::pop(*this);
            break;
        case OpCode::SPUSH:
            MachineOperation::spush(*this);
            break;
        case OpCode::RPUSH:
            MachineOperation::rpush(*this);
            break;
        case OpCode::RSET:
            MachineOperation::rset(*this);
            break;
        case OpCode::JUMP:
            MachineOperation::jump(*this);
            break;
        case OpCode::CJUMP:
            MachineOperation::cjump(*this);
            break;
        case OpCode::STACKEMPTY:
            MachineOperation::stackEmpty(*this);
            break;
        case OpCode::PCPUSH:
            MachineOperation::pcPush(*this);
            break;
        case OpCode::AUXPUSH:
            MachineOperation::auxPush(*this);
            break;
        case OpCode::AUXPOP:
            MachineOperation::auxPop(*this);
            break;
        case OpCode::AUXSTACKEMPTY:
            MachineOperation::auxStackEmpty(*this);
            break;
        case OpCode::NOP:
            ++pc;
            break;
        case OpCode::ERRPUSH:
            MachineOperation::errPush(*this);
            break;
        case OpCode::ERRSET:
            MachineOperation::errSet(*this);
            break;
            /****************************************/
            /*  Duplication and Exchange Operations */
            /****************************************/
        case OpCode::DUP0:
            MachineOperation::dup0(*this);
            break;
        case OpCode::DUP1:
            MachineOperation::dup1(*this);
            break;
        case OpCode::DUP2:
            MachineOperation::dup2(*this);
            break;
        case OpCode::SWAP1:
            MachineOperation::swap1(*this);
            break;
        case OpCode::SWAP2:
            MachineOperation::swap2(*this);
            break;
            /*********************/
            /*  Tuple Operations */
            /*********************/
        case OpCode::TGET:
            MachineOperation::tget(*this);
            break;
        case OpCode::TSET:
            MachineOperation::tset(*this);
            break;
        case OpCode::TLEN:
            MachineOperation::tlen(*this);
            break;
            /***********************/
            /*  Logging Operations */
            /***********************/
        case OpCode::BREAKPOINT:
            return MachineOperation::breakpoint(*this);
        case OpCode::LOG:
            MachineOperation::log(*this);
            break;
        case OpCode::DEBUG:
            MachineOperation::debug(*this);
            break;
            /**********************/
            /*  System Operations */
            /**********************/
        case OpCode::SEND:
            return MachineOperation::send(*this);
        case OpCode::NBSEND:
            MachineOperation::nbsend(*this);
            break;
        case OpCode::GETTIME:
            MachineOperation::getTime(*this);
            break;
        case OpCode::INBOX:
            return MachineOperation::inboxOp(*this);
        case OpCode::ERROR:
            state = Status::Error;
            break;
        case OpCode::HALT:
            state = Status::Halted;
            break;
        default:
            std::cerr << "Unhandled opcode <" << InstructionNames.at(opcode)
                      << ">" << std::hex << static_cast<int>(opcode);
            state = Status::Error;
    }
    return NotBlocked{};
}
