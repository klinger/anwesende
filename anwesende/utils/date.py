import datetime as dt
import re
import typing as tg

import arrow
import django.utils.timezone as djut


def dtstring(dtobj, date=True, time=False) -> str:
    local_dt = djut.localtime(dtobj)
    if date and time:
        format = "%Y-%m-%d %H:%M"
    elif date:
        format = "%Y-%m-%d"
    elif time:
        format = "%H:%M"
    else:
        assert False, "You don't want an empty nowstring, do you?"
    return local_dt.strftime(format)


def nowstring(date=True, time=False) -> str:
    now = djut.localtime()
    return dtstring(now, date, time)


def make_dt(dto: tg.Union[dt.datetime, str], timestr: str = None) -> dt.datetime:
    """Return a datetime with dto date (today if "now") and timestr hour/minute."""
    # 1. Must never use dt.datetime(..., tzinfo=...) with pytz,
    # because it will often end up with a historically outdated timezone.
    # see http://pytz.sourceforge.net/
    # 2. We must not rely on a naive datetime_obj.day etc. because it may be off
    # wrt the server's TIME_ZONE, which we use for interpreting timestr.
    # 3. Django uses UTC timezone on djut.now()! Use djut.localtime().
    if dto == 'now':
        dto = djut.localtime()
    assert isinstance(dto, dt.date)
    assert dto.tzinfo is not None  # reject naive input: we need a tz
    if timestr:
        mm = re.match(r"^(\d\d):(\d\d)$", timestr)
        assert mm, f"must use hh:mm timestr format: {timestr}"
        hour, minute = (int(mm.group(1)), int(mm.group(2)))
    else:
        hour, minute = (dto.hour, dto.minute)
    return arrow.Arrow(*(dto.year, dto.month, dto.day, hour, minute),
                       tzinfo=djut.get_current_timezone()).datetime
