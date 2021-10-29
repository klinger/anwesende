import datetime as dt
import re
import typing as tg

import pytest

import anwesende.room.excel as are
import anwesende.room.models as arm
import anwesende.room.tests.test_excel as artte
import anwesende.users.models as aum

# #### scaffolding:

excel_rooms1_filename = "anwesende/room/tests/data/rooms1.xlsx"
excel_rooms2_filename = "anwesende/room/tests/data/rooms2.xlsx"

@pytest.mark.django_db
def test_displayable_importsteps():
    user = aum.User.objects.create(username="user1")
    # ----- create importstep1:
    stuff1 = are.create_seats_from_excel(excel_rooms1_filename, user)
    print(stuff1)
    # ----- check importstep1:
    assert arm.Importstep.objects.all().count() == 1
    importstep1 = arm.Importstep.objects.first()
    assert importstep1
    assert importstep1.num_existing_rooms == 0
    assert importstep1.num_existing_seats == 0
    assert importstep1.num_new_rooms == 2
    assert importstep1.num_new_seats == 20
    # ----- check displayable importstep1:
    steps1 = arm.Importstep.displayable_importsteps(dt.timedelta(days=1))
    assert len(steps1) == 1
    step1 = steps1[0]
    assert step1.num_existing_rooms == 0
    assert step1.num_existing_seats == 0
    assert step1.num_new_rooms == 2
    assert step1.num_new_seats == 20
    assert step1.num_qrcodes == 20  # type: ignore[attr-defined]
    assert step1.num_qrcodes_moved == 0  # type: ignore[attr-defined]
    # ----- create importstep2:
    stuff2 = are.create_seats_from_excel(excel_rooms2_filename, user)
    print(stuff2)
    # ----- check importstep2:
    assert arm.Importstep.objects.all().count() == 2
    importstep2 = arm.Importstep.objects.order_by('when').last()
    assert importstep2
    assert importstep2.num_existing_rooms == 1
    assert importstep2.num_existing_seats == 6
    assert importstep2.num_new_rooms == 0
    seats = arm.Seat.objects.filter(room__importstep=importstep2)
    for i, seat in enumerate(seats):
        print(i, seat)
    assert importstep2.num_new_seats == 2
    updated_seat = arm.Seat.objects.get(room__room='K40', seatnumber=1, rownumber=1)
    assert abs(updated_seat.room.row_dist - 1.2) < 0.0001  # no longer 1.1
    # ----- check displayable importstep1 again:
    steps2 = arm.Importstep.displayable_importsteps(dt.timedelta(days=1))
    assert len(steps2) == 2
    step1b = steps2[0]  # order is oldest first
    assert step1b.num_new_seats == 20
    # first room is untouched, second room was updated:
    assert step1b.num_qrcodes == 14  # type: ignore[attr-defined]
    assert step1b.num_qrcodes_moved == 6  # type: ignore[attr-defined]
    # ----- check displayable importstep2:
    step2 = steps2[1]
    assert step2.num_existing_rooms == 1
    assert step2.num_existing_seats == 6
    assert step2.num_new_rooms == 0
    assert step2.num_new_seats == 2
    assert step2.num_qrcodes == 8  # type: ignore[attr-defined]
    assert step2.num_qrcodes_moved == 0  # type: ignore[attr-defined]