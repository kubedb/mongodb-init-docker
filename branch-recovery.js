// Copyright The KubeDB Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Re-points one cloned member at the branch. branch-recovery.sh runs it against a
// standalone mongod after the clone's own oplog has been replayed and checkpointed, so
// nothing replayed later can overwrite what it writes. BRANCH is prepended by the
// script: {component, hosts: {srcPrefix: tgtPrefix}, fallbackConfig}.

function mapHost(h) {
  for (const from of Object.keys(BRANCH.hosts)) {
    if (h.startsWith(from)) return BRANCH.hosts[from] + h.slice(from.length);
  }
  return null;
}
function mapDSN(dsn) {
  const i = dsn.indexOf("/");
  const hosts = dsn.slice(i + 1).split(",").map(mapHost).filter(h => h !== null);
  if (hosts.length === 0) throw new Error("no host of " + dsn + " belongs to the branch");
  return dsn.slice(0, i + 1) + hosts.join(",");
}

const local = db.getSiblingDB("local");
const cfg = local.system.replset.findOne();
if (cfg === null) {
  print("the clone holds no replica-set config; seeding the branch's own");
  local.system.replset.insertOne(BRANCH.fallbackConfig);
} else {
  const kept = [];
  for (const m of cfg.members) {
    const h = mapHost(m.host);
    if (h === null) {
      print("dropping member " + m.host + ": it has no place in the branch");
      continue;
    }
    m.host = h;
    kept.push(m);
  }
  if (kept.length === 0) throw new Error("no member of the cloned replica-set config belongs to the branch");
  cfg.members = kept;
  cfg.version = cfg.version + 1;
  local.system.replset.replaceOne({_id: cfg._id}, cfg);
  print("re-pointed replica set " + cfg._id + " at the branch: " + kept.map(m => m.host).join(","));
}

if (BRANCH.component === "configsvr") {
  const conf = db.getSiblingDB("config");
  conf.shards.find().forEach(s => {
    conf.shards.updateOne({_id: s._id}, {$set: {host: mapDSN(s.host)}});
  });
  conf.mongos.deleteMany({});
}
if (BRANCH.component === "shard") {
  const admin = db.getSiblingDB("admin");
  admin.system.version.find({configsvrConnectionString: {$exists: true}}).forEach(d => {
    admin.system.version.updateOne({_id: d._id}, {$set: {configsvrConnectionString: mapDSN(d.configsvrConnectionString)}});
  });
  const conf = db.getSiblingDB("config");
  conf.getCollectionNames().filter(n => n.startsWith("cache.")).forEach(n => conf.getCollection(n).drop());
}
