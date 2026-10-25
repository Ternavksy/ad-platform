from django.http import JsonResponse


def index(request):
    return JsonResponse({"service": "admin-panel", "status": "ok"})


def health(request):
    return JsonResponse({"status": "ok"})
