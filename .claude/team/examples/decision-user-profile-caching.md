# Decision: Implement Redis Cache for User Profile Data

## Decision Record

### Date
2026-02-15

### Decider(s)
- **Systems Architect:** Alex Rivera
- **Team Lead (Approval):** Engineering Team Lead
- **Security Review:** Security Engineer

### Status
- [x] Proposed
- [x] Accepted
- [ ] Deprecated
- [ ] Superseded

---

## Context

**Problem Statement:**
Our user service experiences significant database load during peak traffic periods. User profile queries account for 40% of database traffic, with many duplicate requests for the same user (from multiple API endpoints, different service instances, browser caching).

**Current Situation:**
- Peak load: 1,000 API requests/second
- User profile queries: 400 RPS to PostgreSQL (9% P99 latency: 200-250ms)
- Database connection pool utilization: 85-95% during peaks
- Three service instances serving user requests (no cross-instance cache sharing)
- Each instance reduplicated profile queries independently

**Constraints:**
- Time: Need deployment within 3 weeks
- Infrastructure: Existing AWS footprint (can use ElastiCache)
- Team expertise: Familiar with Redis (used in previous projects)
- Budget: <$1000/month additional infrastructure cost
- Data freshness: User profile changes should reflect within 5-10 seconds

**Why Now:**
Recent marketing campaign increased user base 50%; we're hitting database scaling limits sooner than expected. Need intermediate solution before database sharding (planned for Q3).

---

## Decision

**We will implement a Redis cache layer for user profile data, using a write-through caching pattern with 10-second TTL, to reduce database load and improve P99 latency from 200-250ms to <50ms.**

---

## Rationale

This decision was made based on consultation with the **architect-decisions.md** caching framework and **architect-patterns.md** caching patterns.

### Key Benefits

**1. Performance Improvement (Primary)**
- Redis read latency: 10-20ms (vs PostgreSQL 200-250ms P99)
- Effective P99 reduction: 200-250ms → 40-60ms (20% improvement)
- Addresses immediate peak traffic problem (3-week timeline)
- Reference: architect-decisions.md § Caching Solutions - Latency Thresholds (section shows <50ms target achievable with in-memory solutions)

**2. Database Load Reduction**
- Estimated 30-40% reduction in user profile queries to PostgreSQL
- Alleviates connection pool exhaustion (85-95% → 50-60% expected)
- Extends database headroom until sharding implementation (Q3)
- Reference: architect-decisions.md § Caching Solutions - Read Volume (section shows cache layer for >1k RPS scenarios)

**3. Cross-Instance Consistency**
- Redis Cluster handles cross-instance invalidation automatically
- All three service instances see consistent user data
- Eliminates duplicate profile queries (each instance maintains local copy in memory)
- Reference: architect-patterns.md § Repository Pattern (section describes distributed cache patterns)

**4. Operational Simplicity**
- Write-through caching pattern: simple to implement and reason about
- Team familiar with Redis; existing monitoring/operational procedures applicable
- AWS ElastiCache provides managed cluster (reduces operational overhead)
- 10-second TTL balances consistency needs with cache efficiency
- Reference: architect-decisions.md § Caching Solutions - Operation Complexity

**5. Failure Isolation**
- Cache misses don't block user requests (fail-open to PostgreSQL)
- Database continues to serve requests if cache unavailable
- No "cache stampede" risk (write-through pattern prevents thundering herd)
- Reference: architect-patterns.md § Error Handling Patterns - Graceful Degradation

### How It Addresses the Problem

1. **Reduces database load:** Queries decreases by ~30-40%, alleviating peak load pressure
2. **Improves P99 latency:** 200-250ms → 40-60ms meets user experience expectations
3. **Enables 3-week timeline:** Redis is straightforward; no complex state management required
4. **Provides bridge solution:** Buys time for database sharding implementation (Q3)

---

## Alternatives

### Alternative 1: Database Query Optimization (Indexing, Connection Pooling)
- **Why rejected:** Already optimized; add more database resources (vertical scaling) hits AWS instance limits in 6 months
- **Trade-off:** Less upfront cost, but doesn't solve fundamental load problem; extends timeline for sharding decision
- **Verdict:** Insufficient for current growth trajectory

### Alternative 2: Memcached Instead of Redis
- **Why rejected:** No built-in persistence; cluster rebalancing causes complete cache loss; requires disaster recovery procedures
- **Trade-off:** Slightly simpler deployment, but session data loss during rolling updates is unacceptable
- **Verdict:** Too risky for business-critical user profile data

### Alternative 3: Database Read Replica + Read Balancing
- **Why rejected:** Read replicas add 50-100ms latency (replication lag); still slower than Redis
- **Trade-off:** More distributed and durable, but doesn't meet <50ms latency target
- **Verdict:** Doesn't solve stated problem (P99 latency)

### Alternative 4: GraphQL DataLoader + Application-Level Memory Caching
- **Why rejected:** Caches isolated to each process; lost on restart; doesn't share across three service instances
- **Trade-off:** Zero infrastructure cost, but limited effectiveness for this scale
- **Verdict:** Doesn't provide cross-instance consistency needed for 1k RPS

### Alternative 5: Implement Database Sharding Now
- **Why rejected:** 8-12 week implementation timeline; unacceptable for current load problem
- **Trade-off:** Permanent solution, but too slow for immediate need
- **Verdict:** Implement sharding in Q3 after bridge solution in place

---

## Consequences

### Positive Consequences

1. **Immediate Load Reduction**
   - User profile query database load: 400 RPS → 240-280 RPS (40% reduction)
   - Connection pool utilization: 85-95% → 50-65% (significant improvement)
   - Peak traffic sustainable without database scaling

2. **User Experience Improvement**
   - API P99 latency: 200-250ms → 40-60ms
   - Faster page loads and reduced user complaints
   - Better competitive positioning (performance is feature)

3. **Operational Breathing Room**
   - 6-month runway until database reaches saturation again
   - Time to plan and implement database sharding without emergency pressure
   - Flexibility to adjust architecture based on growth patterns

4. **Cost Effective**
   - ElastiCache 3-node cluster: ~$500/month
   - vs. database vertical scaling (next tier): ~$3,000/month
   - vs. emergency sharding effort: 200+ engineering hours (~$40k)

5. **Team Knowledge**
   - Team already familiar with Redis; reduced learning curve
   - Reinforces caching pattern knowledge for future applications
   - Reference: architect-patterns.md § Repository Pattern (team can reuse pattern in other services)

### Negative Consequences / Trade-offs

1. **Operational Complexity**
   - New infrastructure to monitor: Redis cluster failover, replication lag, memory utilization
   - Require alerts for: redis command duration, connection pool exhaustion, cache hit rate
   - Need runbook for: cache key poisoning, cluster recovery, cache invalidation

2. **Cache Consistency Risks**
   - 10-second TTL means stale data is possible (users see outdated profile for up to 10s after update)
   - Cache invalidation on profile updates must be reliable (bugs can hide stale data)
   - Cross-service profile updates may not immediately propagate

3. **Dependency Fragility**
   - Service now depends on Redis availability
   - Network partition causes cache misses (fail-open means hitting database harder)
   - Single-region failure would impact all three service instances

4. **Infrastructure Cost**
   - Recurring $500/month cost
   - Cost increases if we scale to 5+ service instances
   - Must justify cost in quarterly reviews

### Long-term Implications

**6-12 Month Timeline:**
- Redis suitable for projected load (1,000-2,000 RPS)
- Plan database sharding implementation in Q3 2026
- Implement when projected load reaches 2,000+ RPS

**12-24 Month Timeline:**
- Database sharding deployed; can remove Redis cache layer
- OR: Upgrade to larger Redis cluster if caching benefits persist
- Decision point: Is caching valuable for other use cases?

**Beyond 2 Years:**
- Reassess architecture once sharding reduces database load
- Consider caching for other high-volume queries (e.g., product data, recommendations)
- Redis experience applicable to event-driven architecture (pub/sub for future features)

---

## Implementation Notes

### Prerequisites

1. **AWS ElastiCache Cluster**
   - 3-node Redis cluster (replication factor 1 for cost, multi-AZ for high availability)
   - Parameter group: maxmemory-policy=allkeys-lru (evict least-used keys when full)
   - Network: VPC security group allowing port 6379 from service instances

2. **Application Dependencies**
   - Go redis client: github.com/redis/go-redis/v9
   - Connection pooling: 10-50 connections per service instance (tune based on load)

3. **Monitoring Setup**
   - CloudWatch dashboards for Redis metrics (ops/sec, connections, evictions)
   - Alerts: P99 command latency >50ms, key evictions rate increase >10%/sec, memory util >80%

### Implementation Steps

**Phase 1: Setup (Week 1)**
1. Provision ElastiCache cluster in AWS Terraform
   ```terraform
   resource "aws_elasticache_cluster" "user_profile_cache" {
     cluster_id           = "user-profile-cache"
     engine               = "redis"
     node_type            = "cache.t3.small"
     num_cache_nodes      = 3
     parameter_group_name = "user-profile-cache-params"
     port                 = 6379
   }
   ```

2. Configure Redis cluster parameters
   - maxmemory: 1GB per node (3GB total)
   - maxmemory-policy: allkeys-lru
   - timeout: 300 seconds

3. Setup CloudWatch monitoring
   - Dashboard: Redis ops/sec, connection count, cache hit ratio
   - Alarms: P99 latency, memory util, eviction rate

**Phase 2: Application Changes (Weeks 1-2)**

1. Create Redis client with connection pooling
   ```go
   // user-service/cache/redis.go
   type ProfileCache struct {
       client *redis.Client
   }

   func NewProfileCache(addr string) *ProfileCache {
       return &ProfileCache{
           client: redis.NewClient(&redis.Options{
               Addr:         addr,
               PoolSize:     20,
               MaxRetries:   3,
               ReadTimeout:  3 * time.Second,
               WriteTimeout: 3 * time.Second,
           }),
       }
   }
   ```

2. Implement write-through caching pattern
   ```go
   func (c *ProfileCache) GetProfile(ctx context.Context, userID string) (*Profile, error) {
       // Try cache first
       cacheKey := fmt.Sprintf("user:profile:%s", userID)
       cached, err := c.client.Get(ctx, cacheKey).Result()
       if err == nil {
           // Cache hit; unmarshal and return
           var profile Profile
           if err := json.Unmarshal([]byte(cached), &profile); err != nil {
               // Log error, fall through to database
           } else {
               return &profile, nil
           }
       }

       // Cache miss; fetch from database
       profile, err := db.GetProfile(ctx, userID)
       if err != nil {
           return nil, err
       }

       // Write to cache (fail-open: don't block on cache write)
       profileJSON, _ := json.Marshal(profile)
       c.client.Set(ctx, cacheKey, profileJSON, 10*time.Second)

       return profile, nil
   }
   ```

3. Implement cache invalidation on profile updates
   ```go
   func (c *ProfileCache) UpdateProfile(ctx context.Context, userID string, updates *Profile) error {
       // Update database
       err := db.UpdateProfile(ctx, userID, updates)
       if err != nil {
           return err
       }

       // Invalidate cache (blocking; ensure consistency)
       cacheKey := fmt.Sprintf("user:profile:%s", userID)
       _ = c.client.Del(ctx, cacheKey).Err()

       return nil
   }
   ```

4. Add cache metrics instrumentation
   ```go
   // Track cache hit rate
   prometheus.RegisterCounter("cache_hits", "Total cache hits")
   prometheus.RegisterCounter("cache_misses", "Total cache misses")
   prometheus.RegisterHistogram("cache_latency", "Cache operation latency")
   ```

**Phase 3: Testing (Week 2)**

1. Unit tests for cache logic
   - Test cache hit scenario
   - Test cache miss + database fallback
   - Test cache invalidation

2. Load testing
   - Simulate 1,000 RPS load on cache-enabled service
   - Measure P50, P95, P99 latencies
   - Verify no cache stampede on cluster failure

3. Failure testing
   - Kill one Redis node; verify failover <2 seconds
   - Network partition Redis cluster; verify fail-open to database
   - Cache full; verify LRU eviction doesn't cause errors

**Phase 4: Deployment (Week 3)**

1. Blue-green deployment
   - Deploy cache-enabled version to canary (10% of traffic)
   - Monitor metrics for 4 hours
   - If stable, increase to 100%

2. Metrics validation
   - P99 latency: <60ms (target <50ms)
   - Cache hit rate: >85% (based on typical profile query patterns)
   - Database query reduction: >30%

3. Rollback procedure
   - If P99 latency doesn't improve or hit rate <80%, disable caching
   - Keep Redis infrastructure running (cost low; useful for debugging)

### Rollback Plan

**If Performance Doesn't Improve:**
1. Disable Redis usage in application (feature flag)
   ```go
   if os.Getenv("USE_PROFILE_CACHE") == "true" {
       return cacheClient.GetProfile(ctx, userID)
   }
   return db.GetProfile(ctx, userID)  // fallback to direct database
   ```
2. Monitor database latency return to baseline
3. Analyze why caching didn't help (query patterns, hit rate, etc.)
4. Iterate on cache key strategy or TTL

**If Redis Cluster Fails:**
1. Service continues functioning (fail-open to database)
2. Database load increases but doesn't block user requests
3. Emergency procedure: Scale up database instance (temporary measure)
4. Investigate Redis failure (logs, monitoring)

### Testing Strategy

**Performance Testing:**
- Load test tool: Apache JMeter or custom Go load generator
- Scenario: 1,000 concurrent users, 1,000 RPS for 30 minutes
- Metrics: P50, P95, P99 latencies; cache hit rate; database query count
- Success criteria: P99 <60ms, cache hit rate >85%, database RPS <280

**Failure Testing:**
- Inject Redis latency: 50ms, 100ms, 200ms (simulate network issues)
- Simulate Redis node failure: stop one node during load test
- Verify: Service continues, database absorbs increased load, latencies acceptable

**Data Consistency Testing:**
- Concurrent profile updates from multiple service instances
- Verify: Cache invalidation propagates within 1 second
- Check: No stale data returned beyond 10-second TTL

### Monitoring / Observability

**Key Metrics to Track:**

| Metric | Alert Threshold | Action |
|--------|-----------------|--------|
| redis_command_duration_p99 | >50ms | Page on-call; investigate slow commands |
| redis_connections | >40 | Check connection leak; redeploy if needed |
| redis_evictions_rate | >100/sec | Increase maxmemory; potential memory leak |
| cache_hit_rate | <75% | Investigate query patterns; consider longer TTL |
| cache_staleness | >10s | Check cache invalidation logic |
| database_query_count | >350 RPS | Cache not effective; debug profile query patterns |

**CloudWatch Dashboards:**
```
Dashboard: User Profile Cache
┌─────────────────────────────────────┐
│ Cache Hit Rate (%)   │ P99 Latency  │
│ 87% (Good)          │ 42ms (Good)  │
├─────────────────────────────────────┤
│ Redis Ops/Sec       │ Connections  │
│ 800 ops/sec         │ 25/40 pool   │
├─────────────────────────────────────┤
│ DB Query Reduction  │ Memory Used  │
│ 35% (Good)          │ 2.1GB / 3GB  │
└─────────────────────────────────────┘
```

**Alerts:**
1. `redis_p99_latency > 50ms` → Page on-call; check Redis cluster health
2. `cache_hit_rate < 75%` → Page on-call; investigate query patterns
3. `db_query_count > 350` → Investigate; potential cache issue
4. `redis_evictions > 100/sec` → Increase cluster size or reduce TTL
5. `redis_cluster_node_down` → Critical alert; initiate failover procedure

---

## References

This decision references the Architect Libraries:

### architect-decisions.md
- **Section:** Caching Solutions § Weighted Criteria
  - Data Volume: User profiles ~500MB (suitable for in-memory cache)
  - Consistency Requirements: Eventual consistency acceptable (10s TTL)
  - Query Patterns: Key-value lookups (perfect for cache)
  - Read Volume: 400 RPS (within cache capability)
  - Latency Requirements: <50ms target (achievable with Redis)

- **Section:** Caching Solutions § Decision Tree
  - "Do you need <50ms latency?" → Yes → In-memory cache (Redis, Memcached)
  - "Can you tolerate eventual consistency?" → Yes (10s) → TTL-based expiration acceptable

- **Section:** Caching Solutions § Options Matrix (Comparison)
  - Redis: Selected for write-through pattern, built-in persistence, cluster support

### architect-patterns.md
- **Section:** Structural Patterns § Repository Pattern
  - Implements caching abstraction: `ProfileCache` repository pattern
  - Hides Redis implementation behind `GetProfile()` interface
  - Enables future swapping to different cache backend

- **Section:** Error Handling Patterns § Graceful Degradation
  - Cache misses don't block requests
  - Fail-open to database if Redis unavailable
  - Network partitions result in slightly degraded performance, not errors

### architect-validation.md
- **Section:** Performance Checks § N+1 Query Detection
  - Caching prevents N+1 queries (each profile fetch goes to Redis first)
  - Multiple API endpoints querying same user → single database hit (with cache layer)

- **Section:** Performance Checks § Acceptable Thresholds
  - In-memory cache P99 latency: <50ms ✓ (Redis typical: 10-20ms)
  - Cache hit rate threshold: >80% (our projection: 85-90%)

### architect-security.md
- **Section:** STRIDE Threat Model § Tampering with Data
  - Redis cluster uses network encryption (TLS in-transit)
  - Cache invalidation prevents serving stale sensitive data indefinitely
  - 10-second TTL bounds stale data exposure

- **Section:** Data Protection
  - User profile data sensitivity: Medium (PII, but not financial)
  - Cache encryption: At-rest (AWS ElastiCache managed keys)
  - Monitoring: Log cache hits/misses for audit trail

---

## Related Decisions

- **Blocks:** Q3 2026 Database Sharding Decision
  - This caching solution provides bridge; sharding required long-term
  - Sharding timeline now flexible (6-month window instead of immediate)

- **Related To:** User Service API Design Decision (2026-02-10)
  - API includes `Cache-Control: max-age=10` headers for client-side caching
  - Server-side cache complements client-side strategies

- **Supersedes:** 2025-12-01 Database Vertical Scaling (rejected) Decision
  - Caching chosen over database upgrade for better ROI and timeline

---

## Notes

### Key Discussion Points
- **Team familiarity with Redis:** Team has 18+ months production experience with Redis (messaging use case); reduced risk
- **Cost-benefit:** $500/month cost vs. 6-month engineering timeline for sharding = excellent ROI
- **Monitoring overhead:** Requires adding 5-6 Redis metrics to observability; existing team has expertise

### Dissenting Opinions
- **One team member suggested:** Implement GraphQL DataLoader client-side caching instead
  - Response: Doesn't solve cross-instance consistency; only works for single service instance
  - Caching decision prevailed for cross-instance needs

- **Infrastructure team noted:** Prefer managed AWS services; ElastiCache is managed solution, approved

### Future Considerations
- **Evaluate at 1,500 RPS:** Reassess if caching still effective or if sharding timing should accelerate
- **Explore:**  Cache warming strategies (preload hot user profiles on startup) after 2 weeks live
- **Plan:** Multi-region Redis (Active-Active) if we expand to multiple regions (2027+)

---

## Approval

| Role | Name | Date | Email | Signature |
|------|------|------|-------|-----------|
| Systems Architect | Alex Rivera | 2026-02-15 | alex@company.com | ✓ Approved |
| Engineering Lead | Jane Smith | 2026-02-15 | jane@company.com | ✓ Approved |
| Security Engineer | Bob Wilson | 2026-02-15 | bob@company.com | ✓ Approved (with TLS requirement) |

---

## Decision Tracking

- **Decision ID:** 2026-02-15-user-profile-caching
- **Document Path:** `/skills/team/examples/decision-user-profile-caching.md`
- **Review Cycles:** Initial (2026-02-15), 1-month review (2026-03-15), 3-month evaluation (2026-05-15)
- **Owner:** Systems Architect
