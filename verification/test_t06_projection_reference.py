"""Semantic counterexamples, independent of the old RTL-vs-RTL image oracle."""
import unittest
import numpy as np
from model.reference.model import Camera,Gaussian3D,RenderConfig
from model.reference.math3d import project_gaussian
class ProjectionFrustumRegression(unittest.TestCase):
    def test_offscreen_near_splat_does_not_become_fullscreen(self):
        camera=Camera(16,10,16.,16.,7.5,4.5)
        g=Gaussian3D(0,np.array([-20.,2.,.21]),np.array([.1,.1,.1]),np.array([1.,0.,0.,0.]),.8,rgb=np.array([.4,.3,.2]))
        self.assertIsNone(project_gaussian(g,camera,RenderConfig()))
    def test_in_fov_covariance_and_center_unchanged(self):
        camera=Camera(16,10,4.,4.,7.5,4.5)
        g=Gaussian3D(0,np.array([1.,1.,2.]),np.ones(3),np.array([1.,0.,0.,0.]),.8,rgb=np.ones(3))
        p=project_gaussian(g,camera,RenderConfig(covariance_regularizer=77/256))
        np.testing.assert_allclose(p.mean2d,[9.5,6.5])
        np.testing.assert_allclose(p.covariance2d,[[5+77/256,1],[1,5+77/256]])
if __name__=='__main__':unittest.main()
