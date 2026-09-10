import copy
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from qc import checked, validate_metadata

class QCRegressionTests(unittest.TestCase):
    def setUp(self):
        self.data = {'format':{'duration':'55'},'streams':[
            {'codec_type':'video','width':1080,'height':1920,'codec_name':'h264',
             'pix_fmt':'yuv420p','avg_frame_rate':'30/1','duration':'55','nb_frames':'1650'},
            {'codec_type':'audio','codec_name':'aac','sample_rate':'48000','channels':2,'duration':'55'}]}

    def validate(self, data):
        validate_metadata(data,55,(1080,1920),frames=1650)

    def test_valid(self):
        self.validate(self.data)

    def test_truncated_or_wrong_streams_rejected(self):
        for target,key,value in [('format','duration','1'),(0,'duration','1'),
            (0,'width',1920),(0,'nb_frames','30'),(1,'duration','1'),
            (1,'channels',1),(0,'start_time','0.5')]:
            with self.subTest(key=key,target=target):
                data=copy.deepcopy(self.data)
                (data['format'] if target=='format' else data['streams'][target])[key]=value
                with self.assertRaises(AssertionError): self.validate(data)

    def test_missing_audio_rejected(self):
        self.data['streams'].pop()
        with self.assertRaises(AssertionError): self.validate(self.data)

    def test_ffmpeg_error_even_with_zero_exit_rejected(self):
        with patch('qc.subprocess.run',return_value=SimpleNamespace(returncode=0,stderr='moov atom not found',stdout='')):
            with self.assertRaises(RuntimeError): checked(['ffmpeg'])

if __name__=='__main__': unittest.main()
