-- Tarantool initialization script for ad-platform

box.cfg{
    listen = 33013,
    log_level = 5,
    work_dir = '/var/lib/tarantool',
    memtx_dir = '/var/lib/tarantool',
    vinyl_dir = '/var/lib/tarantool',
    wal_dir = '/var/lib/tarantool'
}

campaigns = box.schema.space.create('campaigns', {
    if_not_exists = true,
    engine = 'memtx'
})

campaigns:create_index('primary', {
    if_not_exists = true,
    type = 'tree',
    parts = {1, 'unsigned'}
})

ads = box.schema.space.create('ads', {
    if_not_exists = true,
    engine = 'memtx'
})

ads:create_index('primary', {
    if_not_exists = true,
    type = 'tree',
    parts = {1, 'unsigned'}
})

creatives = box.schema.space.create('creatives', {
    if_not_exists = true,
    engine = 'memtx'
})

creatives:create_index('primary', {
    if_not_exists = true,
    type = 'tree',
    parts = {1, 'unsigned'}
})

sessions = box.schema.space.create('sessions', {
    if_not_exists = true,
    engine = 'memtx'
})

sessions:create_index('primary', {
    if_not_exists = true,
    type = 'tree',
    parts = {1, 'string'}
})

rate_limits = box.schema.space.create('rate_limits', {
    if_not_exists = true,
    engine = 'memtx'
})

rate_limits:create_index('primary', {
    if_not_exists = true,
    type = 'tree',
    parts = {1, 'string'}
})

user_activity = box.schema.space.create('user_activity', {
    if_not_exists = true,
    engine = 'memtx'
})

user_activity:create_index('primary', {
    if_not_exists = true,
    type = 'tree',
    parts = {1, 'unsigned', 3, 'unsigned'}
})

user_activity:create_index('user_id', {
    if_not_exists = true,
    type = 'tree',
    parts = {1, 'unsigned'}
})

function increment_rate_limit(key, expire_at)
    local tuple = rate_limits:get(key)
    if tuple == nil then
        rate_limits:insert({key, 1, expire_at})
        return 1
    else
        local current_count = tuple[2]
        local current_expire = tuple[3]
        
        if expire_at > current_expire then
            rate_limits:update(key, {{'=', 2, 1}, {'=', 3, expire_at}})
            return 1
        else
            rate_limits:update(key, {{'+', 2, 1}})
            return current_count + 1
        end
    end
end

function clean_expired_rate_limits()
    local now = os.time()
    local expired_keys = {}
    
    for _, tuple in rate_limits:pairs() do
        if tuple[3] < now then
            table.insert(expired_keys, tuple[1])
        end
    end
    
    for _, key in pairs(expired_keys) do
        rate_limits:delete(key)
    end
    
    return #expired_keys
end

box.schema.func.create('clean_expired_rate_limits', {if_not_exists = true})
box.schema.user.grant('guest', 'execute', 'function', 'clean_expired_rate_limits', {if_not_exists = true})

-- box.schema.user.create('app_user', {password = 'secure_password'})
-- box.schema.user.grant('app_user', 'read,write', 'space', 'campaigns')
-- box.schema.user.grant('app_user', 'read,write', 'space', 'ads')
-- box.schema.user.grant('app_user', 'read,write', 'space', 'creatives')
-- box.schema.user.grant('app_user', 'read,write', 'space', 'sessions')
-- box.schema.user.grant('app_user', 'read,write', 'space', 'rate_limits')
-- box.schema.user.grant('app_user', 'read,write', 'space', 'user_activity')

print("Tarantool initialization completed successfully!")