#!/usr/bin/env python3

import json
import os
import re
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

LATITUDE = float(os.environ["WAYBAR_PRAYER_LATITUDE"]) if os.environ.get("WAYBAR_PRAYER_LATITUDE") else None
LONGITUDE = float(os.environ["WAYBAR_PRAYER_LONGITUDE"]) if os.environ.get("WAYBAR_PRAYER_LONGITUDE") else None
CALCULATION_METHOD = 12  # Union Organization Islamic de France (UOIF)
SCHOOL = 0  # Shafi, Maliki, Hanbali
API_URL = "https://api.aladhan.com/v1/timings"
SCHEDULE_NAMES = ("Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha")
PRAYER_NAMES = ("Fajr", "Dhuhr", "Asr", "Maghrib", "Isha")
CACHE_VERSION = 1
RETRY_SECONDS = 300


def cache_path():
    cache_home = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return cache_home / "waybar" / "prayer-times.json"


def detect_timezone():
    timezone_path = Path("/etc/localtime").resolve()
    marker = "/zoneinfo/"
    if marker in str(timezone_path):
        return str(timezone_path).split(marker, 1)[1]

    try:
        timezone_name = Path("/etc/timezone").read_text(encoding="utf-8").strip()
        if timezone_name:
            return timezone_name
    except OSError:
        pass

    return os.environ.get("TZ", "Europe/Paris")


def empty_cache():
    return {
        "version": CACHE_VERSION,
        "latitude": LATITUDE,
        "longitude": LONGITUDE,
        "method": CALCULATION_METHOD,
        "school": SCHOOL,
        "timezone": detect_timezone(),
        "schedules": {},
    }


def load_cache():
    path = cache_path()
    try:
        cache = json.loads(path.read_text(encoding="utf-8"))
        expected = (CACHE_VERSION, LATITUDE, LONGITUDE, CALCULATION_METHOD, SCHOOL)
        actual = tuple(
            cache.get(key)
            for key in ("version", "latitude", "longitude", "method", "school")
        )
        if actual == expected and isinstance(cache.get("schedules"), dict):
            return cache
    except (OSError, ValueError, TypeError):
        pass
    return empty_cache()


def save_cache(cache, reference_date):
    earliest = (reference_date - timedelta(days=1)).isoformat()
    latest = (reference_date + timedelta(days=1)).isoformat()
    cache["schedules"] = {
        key: value
        for key, value in cache["schedules"].items()
        if earliest <= key <= latest
    }

    path = cache_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_suffix(".tmp")
    temporary_path.write_text(
        json.dumps(cache, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    temporary_path.replace(path)


def fetch_schedule(day):
    query = urlencode(
        {
            "latitude": LATITUDE,
            "longitude": LONGITUDE,
            "method": CALCULATION_METHOD,
            "school": SCHOOL,
        }
    )
    request = Request(
        f"{API_URL}/{day.strftime('%d-%m-%Y')}?{query}",
        headers={"User-Agent": "waybar-prayer-times/1.0"},
    )
    with urlopen(request, timeout=10) as response:
        payload = json.load(response)

    if payload.get("code") != 200:
        raise ValueError(payload.get("status", "Prayer time API request failed"))

    data = payload["data"]
    timezone_name = data["meta"]["timezone"]
    ZoneInfo(timezone_name)
    raw_times = data["timings"]
    schedule = {}
    for name in SCHEDULE_NAMES:
        match = re.match(r"^(\d{2}):(\d{2})", raw_times[name])
        if not match:
            raise ValueError(f"Invalid {name} time: {raw_times[name]}")
        schedule[name] = f"{match.group(1)}:{match.group(2)}"

    return schedule, timezone_name


def get_schedule(day, cache, retry_after):
    key = day.isoformat()
    if key in cache["schedules"]:
        return cache["schedules"][key]

    if time.monotonic() < retry_after.get(key, 0):
        return None

    try:
        schedule, timezone_name = fetch_schedule(day)
        cache["timezone"] = timezone_name
        cache["schedules"][key] = schedule
        save_cache(cache, day)
        retry_after.pop(key, None)
        return schedule
    except (OSError, ValueError, KeyError, TypeError, ZoneInfoNotFoundError) as error:
        retry_after[key] = time.monotonic() + RETRY_SECONDS
        print(f"prayer.py: {error}", file=sys.stderr, flush=True)
        return None


def prayer_datetime(day, value, timezone):
    hour, minute = map(int, value.split(":"))
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=timezone)


def output(payload):
    try:
        print(json.dumps(payload, ensure_ascii=False), flush=True)
    except BrokenPipeError:
        raise SystemExit(0)


def main():
    if LATITUDE is None or LONGITUDE is None:
        while True:
            output(
                {
                    "text": "\U0001f54c Configure prayer location",
                    "tooltip": "Set WAYBAR_PRAYER_LATITUDE and WAYBAR_PRAYER_LONGITUDE",
                    "class": "prayer-error",
                    "alt": "error",
                }
            )
            time.sleep(300)

    cache = load_cache()
    retry_after = {}

    while True:
        try:
            timezone = ZoneInfo(cache["timezone"])
        except (KeyError, ZoneInfoNotFoundError):
            cache["timezone"] = detect_timezone()
            timezone = ZoneInfo(cache["timezone"])

        now = datetime.now(timezone)
        today = now.date()
        today_schedule = get_schedule(today, cache, retry_after)

        if not today_schedule:
            output(
                {
                    "text": "\U0001f54c Prayer times unavailable",
                    "tooltip": "Unable to load today's prayer times. Retrying automatically.",
                    "class": "prayer-error",
                    "alt": "error",
                }
            )
        else:
            next_name = None
            next_time = None
            for name in PRAYER_NAMES:
                candidate = prayer_datetime(today, today_schedule[name], timezone)
                if candidate > now:
                    next_name = name
                    next_time = candidate
                    break

            if next_time is None:
                tomorrow = today + timedelta(days=1)
                tomorrow_schedule = get_schedule(tomorrow, cache, retry_after)
                if tomorrow_schedule:
                    next_name = "Fajr"
                    next_time = prayer_datetime(
                        tomorrow, tomorrow_schedule["Fajr"], timezone
                    )

            tooltip = "\n".join(
                f"{name:<8}{today_schedule[name]}" for name in SCHEDULE_NAMES
            )
            if next_time is None:
                output(
                    {
                        "text": "\U0001f54c Next prayer unavailable",
                        "tooltip": tooltip,
                        "class": "prayer-error",
                        "alt": "error",
                    }
                )
            else:
                remaining = max(0, int((next_time - now).total_seconds()))
                hours, remainder = divmod(remaining, 3600)
                minutes = remainder // 60
                output(
                    {
                        "text": f"\U0001f54c {next_name} in {hours:02d}:{minutes:02d}",
                        "tooltip": tooltip,
                        "class": f"prayer-{next_name.lower()}",
                        "alt": next_name.lower(),
                    }
                )

        time.sleep(max(0.05, 1.0 - (time.time() % 1.0)))


if __name__ == "__main__":
    main()
