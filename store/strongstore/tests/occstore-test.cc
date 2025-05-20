#include "store/strongstore/occstore.h"  
#include <gtest/gtest.h>  
  
#include "store/common/transaction.h"  
#include "store/common/frontend/client.h"  
  
namespace strongstore {  
  
class OCCStoreTest : public ::testing::Test {  
protected:  
    void SetUp() override {  
        store = new OCCStore();  
    }  
  
    void TearDown() override {  
        delete store;  
    }  
  
    OCCStore *store;  
};  
  
TEST_F(OCCStoreTest, PrepareTest) {  
    Transaction txn;  
  
      
    Timestamp timestamp(1, 0);  
    txn.addReadSet("key1", timestamp);  
    txn.addWriteSet("key2", "value2");
    Timestamp proposed;  
    int result = store->Prepare(1, txn, timestamp, proposed);  
      
    EXPECT_EQ(REPLY_OK, result);  
}  
  
TEST_F(OCCStoreTest, CommitTest) {  
    Transaction txn;  
    txn.addWriteSet("key1", "value1");  
      
    Timestamp timestamp(1, 0);  
    Timestamp proposed;  
    store->Prepare(1, txn, timestamp, proposed);  
      
    store->Commit(1, timestamp.getTimestamp());  
      
    std::pair<Timestamp, std::string> value_pair;
    int result = store->Get(1, "key1", value_pair);
    
    EXPECT_EQ(REPLY_OK, result);
    EXPECT_EQ("value1", value_pair.second);  
}  
  
  
} // namespace strongstore