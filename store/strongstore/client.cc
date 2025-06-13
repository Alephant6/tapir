// -*- mode: c++; c-file-style: "k&r"; c-basic-offset: 4 -*-
/***********************************************************************
 *
 * store/strongstore/client.cc:
 *   Client to transactional storage system with strong consistency
 *
 * Copyright 2015 Irene Zhang <iyzhang@cs.washington.edu>
 *                Naveen Kr. Sharma <naveenks@cs.washington.edu>
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 **********************************************************************/

#include "store/strongstore/client.h"

using namespace std;

namespace strongstore {

Client::Client(Mode mode, string configPath, int nShards,
                int closestReplica, TrueTime timeServer)
    : transport(0.0, 0.0, 0), mode(mode), timeServer(timeServer)
{
    // Initialize all state here;
    client_id = 0;
    while (client_id == 0) {
        random_device rd;
        mt19937_64 gen(rd());
        uniform_int_distribution<uint64_t> dis;
        client_id = dis(gen);
    }
    t_id = (client_id/10000)*10000;

    nshards = nShards;
    bclient.reserve(nshards);

    Debug("Initializing SpanStore client with id [%lu]", client_id);

    /* Start a client for time stamp server. */
    // if (mode == MODE_OCC) {
    //     string tssConfigPath = configPath + ".tss.config";
    //     ifstream tssConfigStream(tssConfigPath);
    //     if (tssConfigStream.fail()) {
    //         fprintf(stderr, "unable to read configuration file: %s\n",
    //                 tssConfigPath.c_str());
    //     }
    //     transport::Configuration tssConfig(tssConfigStream);
    //     tss = new replication::vr::VRClient(tssConfig, &transport);
    // }

    /* Start a client for each shard. */
    for (int i = 0; i < nShards; i++) {
        string shardConfigPath = configPath + to_string(i) + ".config";
        ShardClient *shardclient = new ShardClient(mode, shardConfigPath,
            &transport, client_id, i, closestReplica);
        bclient[i] = new BufferClient(shardclient);
    }

    /* Run the transport in a new thread. */
    clientTransport = new thread(&Client::run_client, this);

    Debug("SpanStore client [%lu] created!", client_id);
}

Client::~Client()
{
    transport.Stop();
    delete tss;
    for (auto b : bclient) {
        delete b;
    }
    clientTransport->join();
}

/* Runs the transport event loop. */
void
Client::run_client()
{
    transport.Run();
}

/* Begins a transaction. All subsequent operations before a commit() or
 * abort() are part of this transaction.
 *
 * Return a TID for the transaction.
 */
void
Client::Begin()
{
    Debug("BEGIN Transaction");
    t_id++;
    participants.clear();
    commit_sleep = -1;
    for (int i = 0; i < nshards; i++) {
        bclient[i]->Begin(t_id);
    }
}

/* Returns the value corresponding to the supplied key. */
int
Client::Get(const string &key, string &value)
{
    // Contact the appropriate shard to get the value.
    int i = key_to_shard(key, nshards);

    // If needed, add this shard to set of participants and send BEGIN.
    if (participants.find(i) == participants.end()) {
        participants.insert(i);
    }

    // Send the GET operation to appropriate shard.
    Promise promise(GET_TIMEOUT);

    bclient[i]->Get(key, &promise);
    value = promise.GetValue();

    return promise.GetReply();
}

int
Client::BatchGets(const std::vector<std::string> &readKeys, std::vector<std::string> &readValues) 
{
    // Group keys by shard
    std::unordered_map<int, std::vector<size_t>> shardKeyMap;
    for (size_t idx = 0; idx < readKeys.size(); idx++) {
        int shardID = key_to_shard(readKeys[idx], nshards);
        shardKeyMap[shardID].push_back(idx);
    }

    // Prepare space for results
    readValues.resize(readKeys.size());
    int overallStatus = REPLY_OK;

    // For each shard in map
    for (auto &kv : shardKeyMap) {
        int shardID = kv.first;
        auto &indices = kv.second;

        // Mark shard as participant
        if (participants.find(shardID) == participants.end()) {
            participants.insert(shardID);
        }

        // Gather keys for this shard
        std::vector<std::string> shardKeys;
        shardKeys.reserve(indices.size());
        for (size_t idx : indices) {
            shardKeys.push_back(readKeys[idx]);
        }

        // Perform batched get
        Promise promise(GET_TIMEOUT);
        bclient[shardID]->BatchGets(shardKeys, &promise);
        std::vector<std::string> shardValues = promise.GetValues();

        // Copy results back in order
        for (size_t i = 0; i < indices.size(); i++) {
            readValues[indices[i]] = shardValues[i];
        }

        // Check reply
        int reply = promise.GetReply();
        if (reply != REPLY_OK) {
            overallStatus = reply;
        }
    }

    return overallStatus;
}

int
Client::OneShotReadOnly(const std::vector<std::string> &readKeys, std::vector<std::string> &readValues) {
      // Group keys by shard
    std::unordered_map<int, std::vector<size_t>> shardKeyMap;
    for (size_t idx = 0; idx < readKeys.size(); idx++) {
        int shardID = key_to_shard(readKeys[idx], nshards);
        shardKeyMap[shardID].push_back(idx);
    }

    // Prepare space for results
    readValues.resize(readKeys.size());
    int overallStatus = REPLY_OK;

    Timestamp timestamp(timeServer.GetTime(), client_id);

    // For each shard in map
    for (auto &kv : shardKeyMap) {
        int shardID = kv.first;
        auto &indices = kv.second;

        // Mark shard as participant
        if (participants.find(shardID) == participants.end()) {
            participants.insert(shardID);
        }

        // Gather keys for this shard
        std::vector<std::string> shardKeys;
        shardKeys.reserve(indices.size());
        for (size_t idx : indices) {
            shardKeys.push_back(readKeys[idx]);
        }

        // Perform batched get
        Promise promise(GET_TIMEOUT);
        bclient[shardID]->OneShotReadOnly(shardKeys, timestamp, &promise);
        std::vector<std::string> shardValues = promise.GetValues();

        // Copy results back in order
        for (size_t i = 0; i < indices.size(); i++) {
            readValues[indices[i]] = shardValues[i];
        }

        // Check reply
        int reply = promise.GetReply();
        if (reply != REPLY_OK) {
            overallStatus = reply;
        }
    }

    return overallStatus;
}

/* Sets the value corresponding to the supplied key. */
int
Client::Put(const string &key, const string &value)
{
    // Contact the appropriate shard to set the value.
    int i = key_to_shard(key, nshards);

    // If needed, add this shard to set of participants and send BEGIN.
    if (participants.find(i) == participants.end()) {
        participants.insert(i);
    }

    Promise promise(PUT_TIMEOUT);

    // Buffering, so no need to wait.
    bclient[i]->Put(key, value, &promise);
    return promise.GetReply();
}

int
Client::Prepare(Timestamp &timestamp)
{
    // 1. Send commit-prepare to all shards.
    uint64_t proposed = 0;
    list<Promise *> promises;

    Debug("PREPARE [%lu] at %lu", t_id, timestamp.getTimestamp());
    ASSERT(participants.size() > 0);

    for (auto p : participants) {
        promises.push_back(new Promise(PREPARE_TIMEOUT));
        bclient[p]->Prepare(timestamp, promises.back());
    }

    int status = REPLY_OK;
    uint64_t ts;
    // 3. If all votes YES, send commit to all shards.
    // If any abort, then abort. Collect any retry timestamps.
    for (auto p : promises) {
        uint64_t proposed = p->GetTimestamp().getTimestamp();

        switch(p->GetReply()) {
        case REPLY_OK:
            Debug("PREPARE [%lu] OK", t_id);
            continue;
        case REPLY_FAIL:
            // abort!
            Debug("PREPARE [%lu] ABORT", t_id);
            return REPLY_FAIL;
        case REPLY_RETRY:
            status = REPLY_RETRY;
                if (proposed > ts) {
                    ts = proposed;
                }
                break;
        case REPLY_TIMEOUT:
            status = REPLY_RETRY;
            break;
        case REPLY_ABSTAIN:
            // just ignore abstains
            break;
        default:
            break;
        }
        delete p;
    }

    if (status == REPLY_RETRY) {
        uint64_t now = timeServer.GetTime();
        if (now > proposed) {
            timestamp.setTimestamp(now);
        } else {
            timestamp.setTimestamp(proposed);
        }
        Debug("RETRY [%lu] at [%lu]", t_id, timestamp.getTimestamp());
    }

    Debug("All PREPARE's [%lu] received", t_id);
    return status;
}

/* Attempts to commit the ongoing transaction. */
bool
Client::Commit()
{
     // Implementing 2 Phase Commit
    Timestamp timestamp(timeServer.GetTime(), client_id);
    int status;

    for (retries = 0; retries < COMMIT_RETRIES; retries++) {
        status = Prepare(timestamp);
        if (status == REPLY_RETRY) {
            continue;
        } else {
            break;
        }
    }

    if (status == REPLY_OK) {
        Debug("COMMIT [%lu]", t_id);
        
        for (auto p : participants) {
            bclient[p]->Commit(0);
        }
        return true;
    }

    // 4. If not, send abort to all shards.
    Abort();
    return false;
}

// send UnloggedInvoke to one replica
int
Client::ReadOnlyPrepare(Timestamp &timestamp) {
    // 1. Send commit-prepare to all shards.
    uint64_t proposed = 0;
    list<Promise *> promises;

    Debug("ReadOnlyPREPARE [%lu] at %lu", t_id, timestamp.getTimestamp());
    ASSERT(participants.size() > 0);

    for (auto p : participants) {
        promises.push_back(new Promise(PREPARE_TIMEOUT));
        bclient[p]->ReadOnlyPrepare(timestamp, promises.back());
    }

    int status = REPLY_OK;
    uint64_t ts;
    // 3. If all votes YES, send commit to all shards.
    // If any abort, then abort. Collect any retry timestamps.
    for (auto p : promises) {
        uint64_t proposed = p->GetTimestamp().getTimestamp();

        switch(p->GetReply()) {
        case REPLY_OK:
            Debug("ReadOnlyPREPARE [%lu] OK", t_id);
            continue;
        case REPLY_FAIL:
            // abort!
            Debug("ReadOnlyPREPARE [%lu] ABORT", t_id);
            return REPLY_FAIL;
        case REPLY_RETRY:
            status = REPLY_RETRY;
                if (proposed > ts) {
                    ts = proposed;
                }
                break;
        case REPLY_TIMEOUT:
            status = REPLY_RETRY;
            break;
        case REPLY_ABSTAIN:
            // just ignore abstains
            break;
        default:
            break;
        }
        delete p;
    }

    if (status == REPLY_RETRY) {
        uint64_t now = timeServer.GetTime();
        if (now > proposed) {
            timestamp.setTimestamp(now);
        } else {
            timestamp.setTimestamp(proposed);
        }
        Debug("ReadOnlyRETRY [%lu] at [%lu]", t_id, timestamp.getTimestamp());
    }

    Debug("All ReadOnlyPREPARE's [%lu] received", t_id);
    return status;
}

 bool 
 Client::ReadOnlyCommit() {
    // Implementing 2 Phase Commit
    Timestamp timestamp(timeServer.GetTime(), client_id);
    int status;
    Promise *promise = NULL;


    for (retries = 0; retries < COMMIT_RETRIES; retries++) {
        status = ReadOnlyPrepare(timestamp);
        if (status == REPLY_RETRY) {
            continue;
        } else {
            break;
        }
    }

    if (status == REPLY_OK) {
        Debug("ReadOnlyCOMMIT [%lu]", t_id);
        
        for (auto p : participants) {
            bclient[p]->ReadOnlyCommit(0, promise);
        }
        return true;
    }

    // 4. If not, send abort to all shards.
    Abort();
    return false;
 }

/* Aborts the ongoing transaction. */
void
Client::Abort()
{
    Debug("ABORT Transaction");
    for (auto p : participants) {
        bclient[p]->Abort();
    }
}

/* Return statistics of most recent transaction. */
vector<int>
Client::Stats()
{
    vector<int> v;
    return v;
}

/* Callback from a tss replica upon any request. */
void
Client::tssCallback(const string &request, const string &reply)
{
    lock_guard<mutex> lock(cv_m);
    Debug("Received TSS callback [%s]", reply.c_str());

    // Copy reply to "replica_reply".
    replica_reply = reply;
    
    // Wake up thread waiting for the reply.
    cv.notify_all();
}

} // namespace strongstore
