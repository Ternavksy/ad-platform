from django.test import TestCase


class HealthViewsTests(TestCase):
    def test_index(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["service"], "admin-panel")

    def test_health(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_admin_login_page(self):
        response = self.client.get("/admin/login/")
        self.assertEqual(response.status_code, 200)
