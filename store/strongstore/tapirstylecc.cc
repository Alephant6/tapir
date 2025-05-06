#include "store/strongstore/tapirstylecc.h"
using namespace std;
namespace strongstore {


TapirStyleCC::TapirStyleCC() {
  // Constructor implementation
}

TapirStyleCC::~TapirStyleCC() {
  // Destructor implementation
}

int
TapirStyleCC::Prepare(uint64_t id,
                    const Transaction &txn,
                    const Timestamp &timestamp,
                    Timestamp &proposedTimestamp)
{
  // Minimal placeholder
  return REPLY_OK;
}

void
TapirStyleCC::Commit(uint64_t id, uint64_t commitTs)
{
  // Minimal placeholder
}

void
TapirStyleCC::GetPreparedWrites(std::unordered_map<std::string, std::set<Timestamp>> &pWrites)
{
  // Minimal placeholder
}

void
TapirStyleCC::GetPreparedReads(std::unordered_map<std::string, std::set<Timestamp>> &pReads)
{
  // Minimal placeholder
}

} // namespace strongstore
