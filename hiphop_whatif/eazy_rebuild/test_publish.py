import unittest
from datetime import datetime, timedelta, timezone
from publish import confirmed, release_time, result_for

class PublishTests(unittest.TestCase):
    def test_skipped_is_not_success(self):
        self.assertFalse(confirmed({'success':True,'skipped':True}))
        self.assertFalse(confirmed({'success':True,'status':'queued'}))
        self.assertTrue(confirmed({'success':True,'status':'completed'}))

    def test_both_result_shapes(self):
        row={'platform':'youtube','success':True}
        self.assertEqual(result_for({'results':[row]},'youtube'),row)
        self.assertEqual(result_for({'results':{'youtube':row}},'youtube'),row)

    def test_stale_schedule_fails(self):
        with self.assertRaises(ValueError): release_time('2020-01-01T00:00:00Z')
        with self.assertRaises(ValueError): release_time('2030-01-01T00:00:00')
        future=datetime.now(timezone.utc)+timedelta(hours=4)
        self.assertEqual(release_time(future.isoformat()),future)

if __name__=='__main__': unittest.main()
