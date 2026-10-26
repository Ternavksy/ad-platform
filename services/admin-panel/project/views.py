from django.http import JsonResponse


def index(request):
    return JsonResponse({
        "service": "admin-panel",
        "status": "deprecated",
        "message": "Administrative UI is provided by the Flutter Admin Workspace",
    })


def health(request):
    return JsonResponse({"status": "ok"})
