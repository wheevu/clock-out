#include "contracts.HC"
#include <math.h>

Mat4 mat_perspective(double fovy, double asp, double n, double f){
  Mat4 r={{0}};
  double t = 1.0/tan(fovy*0.5);
  r.m[0]=t/asp; r.m[5]=t;
  r.m[10]=-(f+n)/(f-n); r.m[11]=-1.0;
  r.m[14]=-(2*f*n)/(f-n);
  return r;
}
Mat4 mat_lookat(Vec3 eye, Vec3 tgt, Vec3 up){
  Vec3 f = vnorm(vsub(tgt,eye));
  /* proper right vector */
  Vec3 rt = vnorm((Vec3){ f.y*up.z - f.z*up.y, f.z*up.x - f.x*up.z, f.x*up.y - f.y*up.x });
  Vec3 u = (Vec3){ rt.y*f.z - rt.z*f.y, rt.z*f.x - rt.x*f.z, rt.x*f.y - rt.y*f.x };
  Mat4 r={{0}};
  r.m[0]=rt.x; r.m[4]=rt.y; r.m[8]=rt.z;
  r.m[1]=u.x;  r.m[5]=u.y;  r.m[9]=u.z;
  r.m[2]=-f.x; r.m[6]=-f.y; r.m[10]=-f.z;
  r.m[12]=-vdot(rt,eye); r.m[13]=-vdot(u,eye); r.m[14]=vdot(f,eye); r.m[15]=1.0;
  return r;
}
void mat_transform(Mat4 m, Vec3 p, double *x, double *y, double *z, double *w){
  double X=m.m[0]*p.x+m.m[4]*p.y+m.m[8]*p.z+m.m[12];
  double Y=m.m[1]*p.x+m.m[5]*p.y+m.m[9]*p.z+m.m[13];
  double Z=m.m[2]*p.x+m.m[6]*p.y+m.m[10]*p.z+m.m[14];
  double W=m.m[3]*p.x+m.m[7]*p.y+m.m[11]*p.z+m.m[15];
  *x=X; *y=Y; *z=Z; *w=W;
}
