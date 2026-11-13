/* Pure x86 geometry leaf functions: no Ruby pointers, allocation or engine ABI. */
int _fltused = 0;
static int finite_number(double value) {
    union { double d; unsigned long w[2]; } bits;
    bits.d = value;
    return (bits.w[1] & 0x7ff00000UL) != 0x7ff00000UL;
}
static int segment(double x, double y, double dx, double dy,
                   double left, double top, double width, double height, int open) {
    double first = 0.0, last = 1.0, near, far, swap;
    if (dx == 0.0) {
        if (open ? !(x > left && x < left + width) : !(x >= left && x <= left + width)) return 0;
    } else {
        near = (left - x) / dx; far = (left + width - x) / dx;
        if (near > far) { swap = near; near = far; far = swap; }
        if (near > first) first = near;
        if (far < last) last = far;
        if (open ? first >= last : first > last) return 0;
    }
    if (dy == 0.0) {
        if (open ? !(y > top && y < top + height) : !(y >= top && y <= top + height)) return 0;
    } else {
        near = (top - y) / dy; far = (top + height - y) / dy;
        if (near > far) { swap = near; near = far; far = swap; }
        if (near > first) first = near;
        if (far < last) last = far;
        if (open ? first >= last : first > last) return 0;
    }
    return 1;
}
static int hits(const double *q, const double *w) {
    double x=q[0], y=q[1], dx=q[2]-x, dy=q[3]-y, r=q[4];
    double left=w[0], top=w[1], width=w[2], height=w[3];
    double cx, cy, t, length, ex, ey;
    int ix, iy;
    if (q[5] == 1.0) {
        cx = x > left ? x : left; if (cx > left+width) cx = left+width;
        cy = y > top ? y : top; if (cy > top+height) cy = top+height;
        ex=x-cx; ey=y-cy;
        return ex*ex+ey*ey < r*r || (x >= left && x <= left+width && y >= top && y <= top+height);
    }
    if (r == 0.0) return segment(x,y,dx,dy,left,top,width,height,0);
    if (segment(x,y,dx,dy,left-r,top,width+r*2.0,height,1) ||
        segment(x,y,dx,dy,left,top-r,width,height+r*2.0,1)) return 1;
    length=dx*dx+dy*dy;
    for (ix=0; ix<2; ++ix) for (iy=0; iy<2; ++iy) {
        cx=left+(ix ? width : 0.0); cy=top+(iy ? height : 0.0);
        t=length == 0.0 ? 0.0 : ((cx-x)*dx+(cy-y)*dy)/length;
        if (t < 0.0) t=0.0; if (t > 1.0) t=1.0;
        ex=x+dx*t-cx; ey=y+dy*t-cy;
        if (ex*ex+ey*ey < r*r) return 1;
    }
    return 0;
}
static int scan(const double *q, const double *walls, int count, const double *ignore, int ignored) {
    int i,j,skip;
    const double *w,*v;
    for (i=0; i<count; ++i) {
        w=walls+i*4; skip=0;
        for (j=0; j<ignored; ++j) {
            v=ignore+j*4;
            if (w[0]==v[0] && w[1]==v[1] && w[2]==v[2] && w[3]==v[3]) { skip=1; break; }
        }
        if (!skip && hits(q,w)) return 1;
    }
    return 0;
}
__declspec(dllexport) int __stdcall lona_geometry_abi(void) { return 0x010101; }
/* Rectangles: four doubles, bodies: x/y/radius, query: six doubles. */
__declspec(dllexport) int __stdcall lona_geometry(const double *q, const double *walls, int count,
    const double *bodies, int body_count, const double *ignore, int ignored) {
    int i;
    double box[4];
    if (!q || count<0 || body_count<0 || ignored<0 || count>1000000 || body_count>100000 || ignored>100000) return -1;
    if ((count && !walls) || (body_count && !bodies) || (ignored && !ignore)) return -1;
    for (i=0; i<6; ++i) if (!finite_number(q[i])) return -1;
    if (q[4]<0.0) return -1;
    if (scan(q,walls,count,ignore,ignored)) return 1;
    for (i=0; i<body_count; ++i) {
        box[0]=bodies[i*3]-bodies[i*3+2];
        box[1]=bodies[i*3+1]-bodies[i*3+2];
        box[2]=box[3]=bodies[i*3+2]*2.0;
        if (scan(q,box,1,ignore,ignored)) return 1;
    }
    return 0;
}
