import django.core.management.base as djcmb

import anwesende.room.models as arm
import anwesende.users.models as aum


class Command(djcmb.BaseCommand):
    help = "Silently creates group 'datenverwalter'"

    def handle(self, *args, **options):
        dvgroup = aum.User.get_datenverwalter_group()  # so admin has it on first visit
        print(f"created group '{dvgroup.name}'")
        arm.Seat.get_dummy_seat()  # create now to make it nicely the first one
