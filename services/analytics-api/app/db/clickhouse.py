import clickhouse_connect
from app.core.config import settings


class ClickhouseClient:
    def __init__(self):
        self.client = None
    
    def connect(self):
        self.client = clickhouse_connect.get_client(
            host=settings.clickhouse_host,
            port=settings.clickhouse_port,
            database=settings.clickhouse_database,
            username=settings.clickhouse_username,
            password=settings.clickhouse_password
        )
    
    def insert_ad_stats(self, data):
        self.client.insert('ads_stats', data, column_names=[
            'date', 'campaign_id', 'ad_id', 'creative_id', 
            'impressions', 'clicks', 'cost', 'timestamp'
        ])
    
    def insert_campaign_stats(self, data):
        self.client.insert('campaign_stats', data, column_names=[
            'date', 'campaign_id', 'impressions', 'clicks', 'cost', 'timestamp'
        ])
    
    def insert_creative_stats(self, data):
        self.client.insert('creative_stats', data, column_names=[
            'date', 'creative_id', 'impressions', 'clicks', 'cost', 'timestamp'
        ])

    def insert_delivery_stats(self, data):
        self.client.insert('delivery_stats', data, column_names=[
            'event_id', 'delivery_id', 'date', 'campaign_id', 'ad_id',
            'creative_id', 'placement', 'site_id', 'placement_id', 'format_id',
            'placement_code', 'format_code', 'audience_age', 'audience_gender',
            'audience_interests', 'country', 'region', 'city', 'device_type',
            'operating_system', 'impressions', 'clicks', 'conversions',
            'conversion_value', 'conversion_type', 'conversion_currency',
            'attribution_model', 'attribution_window_hours', 'is_fraud',
            'fraud_reason',
            'cost', 'timestamp'
        ])
    
    def get_ad_stats(self, campaign_id: int = None, ad_id: int = None, 
                    start_date: str = None, end_date: str = None):
        query = """
            SELECT date, campaign_id, ad_id, creative_id, 
                   sumIf(impressions, is_fraud = 0) as total_impressions,
                   sumIf(clicks, is_fraud = 0) as total_clicks,
                   sumIf(conversions, is_fraud = 0) as total_conversions,
                   sumIf(conversion_value, is_fraud = 0) as total_conversion_value,
                   sumIf(conversions, is_fraud = 0 AND attribution_model = 'last_click') as last_click_conversions,
                   sumIf(conversions, is_fraud = 0 AND attribution_model = 'view_through') as view_through_conversions,
                   sum(is_fraud) as total_fraud_events,
                   sumIf(cost, is_fraud = 0) as total_cost
            FROM delivery_stats FINAL
            WHERE 1=1
        """
        params = []
        
        if campaign_id:
            query += " AND campaign_id = %s"
            params.append(campaign_id)
        
        if ad_id:
            query += " AND ad_id = %s"
            params.append(ad_id)
        
        if start_date:
            query += " AND date >= %s"
            params.append(start_date)
        
        if end_date:
            query += " AND date <= %s"
            params.append(end_date)
        
        query += " GROUP BY date, campaign_id, ad_id, creative_id ORDER BY date"
        
        return self.client.query(query, parameters=params).result_rows
    
    def get_campaign_stats(self, campaign_id: int = None, 
                          start_date: str = None, end_date: str = None):
        query = """
            SELECT date, campaign_id,
                   sumIf(impressions, is_fraud = 0) as total_impressions,
                   sumIf(clicks, is_fraud = 0) as total_clicks,
                   sumIf(conversions, is_fraud = 0) as total_conversions,
                   sumIf(conversion_value, is_fraud = 0) as total_conversion_value,
                   sumIf(conversions, is_fraud = 0 AND attribution_model = 'last_click') as last_click_conversions,
                   sumIf(conversions, is_fraud = 0 AND attribution_model = 'view_through') as view_through_conversions,
                   sum(is_fraud) as total_fraud_events,
                   sumIf(cost, is_fraud = 0) as total_cost
            FROM delivery_stats FINAL
            WHERE 1=1
        """
        params = []
        
        if campaign_id:
            query += " AND campaign_id = %s"
            params.append(campaign_id)
        
        if start_date:
            query += " AND date >= %s"
            params.append(start_date)
        
        if end_date:
            query += " AND date <= %s"
            params.append(end_date)
        
        query += " GROUP BY date, campaign_id ORDER BY date"
        
        return self.client.query(query, parameters=params).result_rows
    
    def get_creative_stats(self, creative_id: int = None,
                          start_date: str = None, end_date: str = None):
        query = """
            SELECT date, creative_id,
                   sumIf(impressions, is_fraud = 0) as total_impressions,
                   sumIf(clicks, is_fraud = 0) as total_clicks,
                   sumIf(conversions, is_fraud = 0) as total_conversions,
                   sumIf(conversion_value, is_fraud = 0) as total_conversion_value,
                   sumIf(conversions, is_fraud = 0 AND attribution_model = 'last_click') as last_click_conversions,
                   sumIf(conversions, is_fraud = 0 AND attribution_model = 'view_through') as view_through_conversions,
                   sum(is_fraud) as total_fraud_events,
                   sumIf(cost, is_fraud = 0) as total_cost
            FROM delivery_stats FINAL
            WHERE 1=1
        """
        params = []
        
        if creative_id:
            query += " AND creative_id = %s"
            params.append(creative_id)
        
        if start_date:
            query += " AND date >= %s"
            params.append(start_date)
        
        if end_date:
            query += " AND date <= %s"
            params.append(end_date)
        
        query += " GROUP BY date, creative_id ORDER BY date"
        
        return self.client.query(query, parameters=params).result_rows


clickhouse_client = ClickhouseClient()
