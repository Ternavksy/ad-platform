CREATE TABLE IF NOT EXISTS ads(
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    campaign_id BIGINT NOT NULL,
    title VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    CONSTRAINT fk_ads_campaign
        FOREIGN KEY (campaign_id)
        REFERENCES campaigns(id)
        ON DELETE CASCADE
);