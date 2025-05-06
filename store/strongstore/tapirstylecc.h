#pragma once

#include "store/common/backend/txnstore.h"
#include "store/common/timestamp.h"
#include "store/common/transaction.h"
#include <unordered_map>
#include <string>
#include <set>

namespace strongstore {

class TapirStyleCC : public TxnStore
{
public:
    explicit TapirStyleCC();
    virtual ~TapirStyleCC();

    int Prepare(uint64_t id,
                const Transaction &txn,
                const Timestamp &timestamp,
                Timestamp &proposedTimestamp) override;

    void Commit(uint64_t id, uint64_t commitTs) override;

private:
    std::unordered_map<uint64_t, std::pair<Timestamp, Transaction>> prepared;

    void GetPreparedWrites(std::unordered_map<std::string, std::set<Timestamp>> &pWrites);
    void GetPreparedReads(std::unordered_map<std::string, std::set<Timestamp>> &pReads);
};

} // namespace strongstore