import copy
import math
from pprint import pprint
import typing as tg

import django.utils.timezone as djut
from freezegun import freeze_time
import pytest

import anwesende.room.models as arm
import anwesende.users.models as aum
import anwesende.utils.date as aud


def make_organizations(descr) -> None:
    """descr is a nested dict describing orgs, deps, rooms, #seats, like an xlsx."""
    persons = ("p1", "p2", "p3", "p4")
    personindex = 0
    for orgname, orgdescr in descr.items():
        for depname, depdescr in orgdescr.items():
            for roomname, roomdescr in depdescr.items():
                numseats, numvisits = roomdescr
                seats = make_seats(roomname, numseats, organization=orgname,
                                   department=depname)
                for i in range(numvisits):
                    make_visit(seats[i % len(seats)], 
                               persons[personindex % len(persons)])
                    personindex += 1
    
def make_seats(roomname: str, numseats: int, organization="org",
               department="dep") -> tg.Tuple[arm.Seat, ...]:
    importstep = arm.Importstep.objects.first()  # reuse existing, if any
    if not importstep:
        user = aum.User.objects.first() or aum.User.objects.create(name="x")
        importstep = arm.Importstep(user=user)
        importstep.save()
    results = []
    room = arm.Room(organization=organization, department=department, 
                    building="bldg",
                    room=roomname,
                    row_dist=1.3, seat_dist=0.8,
                    seat_last=arm.Seat.form_seatname(1, numseats),
                    importstep=importstep)
    room.save()
    for i in range(numseats):
        seat = arm.Seat(hash=arm.Seat.seathash(room, arm.Seat.form_seatname(1, i + 1)),
                        rownumber=1, seatnumber=i + 1, room=room)
        seat.save()
        results.append(seat)
    return tuple(results)


def make_visit(seat: arm.Seat, person: str, tfrom="03:00", tto="04:00") -> arm.Visit:
    now = djut.localtime()
    present_from = aud.make_dt(now, tfrom)
    present_to = aud.make_dt(now, tto)
    assert present_from < present_to
    v = arm.Visit(givenname=person, familyname="fn",
                  street_and_number="sn", zipcode="12345", town="t",
                  phone=person, email=f"{person}@fn.de",
                  status_3g=arm.G_IMPFT,
                  submission_dt=now,
                  present_from_dt=present_from, present_to_dt=present_to,
                  seat=seat)
    v.save()
    return v


@pytest.mark.django_db
def test_room_descriptor():
    rm1s1, = make_seats("myroom", 1)
    rm2s1, = make_seats("otherroom", 1)
    v1 = make_visit(rm1s1, "p1", "02:00", "04:00")  # noqa
    v2 = make_visit(rm2s1, "p2", "02:00", "04:00")  # noqa
    myroom = arm.Room.objects.get(room="myroom")
    assert myroom.descriptor == "org;dep;bldg;myroom"


@pytest.mark.django_db
def test_usage_statistics():
   descr = dict(org1=
                dict(dep1=
                     dict(room1=(1,1),
                          room2=(2,2)),
                     dep2=
                     dict(room3=(3,4))),
                org2=
                dict(dep3=
                     dict(room4=(4,9),
                          room5=(5,16))))
   make_organizations(descr)
   assert arm.Room.objects.count() == 5
   assert arm.Seat.objects.count() == 15
   assert arm.Visit.objects.count() == 32
   result = list(arm.Room.usage_statistics())
   pprint(result)
   should = [
       {'organization': 'org1', 'department': 'dep1',
          'rooms': 2,  'seats': 3,  'visits': 3},
       {'organization': 'org1', 'department': 'dep2',
          'rooms': 1,  'seats': 3,  'visits': 4},
       {'organization': 'org2', 'department': 'dep3',
          'rooms': 2,  'seats': 9,  'visits': 25} ]
   assert result == should


@pytest.mark.django_db
def test_get_overlapping_visits():
    # test can fail if run very shortly before midnight, just run it again
    rm1s1, rm1s2 = make_seats("room1", 2)
    rm2s1, = make_seats("room2", 1)
    targetvisit = make_visit(rm1s1, "p1", "03:00", "04:00")
    shorttargetvisit = make_visit(rm1s1, "p1", "03:00", "03:01")
    # --- the following other visits have _y if they are to be found, _n if not:
    otherroom_n = make_visit(rm2s1, "p2", "03:00", "04:00")
    before_n = make_visit(rm1s2, "p3", "02:00", "03:00")
    within_y = make_visit(rm1s2, "p4", "03:15", "03:45")
    across_y = make_visit(rm1s2, "p5", "02:00", "05:00")
    after_n = make_visit(rm1s2, "p3", "04:00", "05:00")
    halfbefore_y = make_visit(rm1s2, "p6", "02:30", "03:30")
    halfafter_y = make_visit(rm1s2, "p7", "03:30", "04:30")
    nearlybefore_n = make_visit(rm1s2, "p8", "02:00", "03:01")
    nearlyafter_n = make_visit(rm1s2, "p9", "03:59", "05:00")
    # --- now look which ones appear for targetvisit:
    results = set(targetvisit.get_overlapping_visits())
    result_pks = set(el.pk for el in results)
    expected = set(el.pk for el in (targetvisit, within_y, across_y, halfbefore_y, halfafter_y))
    not_expected = set(el.pk for el in (otherroom_n, before_n, after_n, nearlybefore_n, nearlyafter_n))
    print("result_pks", result_pks)
    print("expected", expected)
    print("not_expected", not_expected)
    assert result_pks.isdisjoint(not_expected)
    assert result_pks == expected
    # --- now look which ones appear for shorttargetvisit:
    assert shorttargetvisit.get_overlapping_visits().count() == 0


@pytest.mark.django_db
def test_current_unique_visitorsN():
    # test can fail if run very shortly before midnight, just run it again
    def show_them(room):
        them = room.current_unique_visitors_qs()
        print ([v.email for v in them])
    rm1s1, rm1s2, rm1s3 = make_seats("room1", 3)
    rm2s1, = make_seats("room2", 1)
    room = rm1s1.room
    person1_early = make_visit(rm1s1, "p1", "02:58", "04:00")  # noqa
    person2_ontime = make_visit(rm1s2, "p2", "03:00", "04:00")  # noqa
    person3_late = make_visit(rm1s3, "p3", "03:03", "04:00")  # noqa
    person4_otherroom = make_visit(rm2s1, "p4", "03:00", "04:00")  # noqa
    person3_changed = make_visit(rm1s1, "p3", "03:30", "04:00")  # noqa
    # --- now look at different times how many are in rm1:
    def freeze_at(ts: str):
        return freeze_time(aud.make_dt('now', ts))
    with freeze_at("02:50"):
        show_them(room)
        assert room.current_unique_visitorsN() == 0
    with freeze_at("02:59"):
        show_them(room)
        assert room.current_unique_visitorsN() == 1
    with freeze_at("03:01"):
        show_them(room)
        assert room.current_unique_visitorsN() == 2
    with freeze_at("03:06"):
        show_them(room)
        assert room.current_unique_visitorsN() == 3
    with freeze_at("03:33"):
        show_them(room)
        assert room.current_unique_visitorsN() == 3
    with freeze_at("05:00"):
        show_them(room)
        assert room.current_unique_visitorsN() == 0


@pytest.mark.django_db
def test_get_dummy_seat():
    dummy1 = arm.Seat.get_dummy_seat()
    dummy2 = arm.Seat.get_dummy_seat()
    assert dummy1 == dummy2  # from DB query, hence not necessarily also 'is' 
    assert arm.Seat.objects.count() == 1


@pytest.mark.django_db
def test_split_seatname():
    dummy = arm.Seat.get_dummy_seat()
    dummy.seatnumber = 3
    assert dummy.seatname == "r1s3"
    assert dummy.seatname == arm.Seat.form_seatname(1, 3)
    assert (1, 3) == dummy.split_seatname(dummy.seatname)


@pytest.mark.django_db
def test_distance_in_m():
    dummy = arm.Seat.get_dummy_seat()
    other = copy.copy(dummy)
    other.rownumber = 2
    other.seatnumber = 3
    r_dist = ((other.rownumber-1) * dummy.room.row_dist)
    s_dist = ((other.seatnumber-1) * dummy.room.seat_dist)
    dist_is = dummy.distance_in_m(other)
    dist_should = math.sqrt(s_dist**2 + r_dist**2)
    assert abs(dist_is - dist_should) < 0.0001
