FROM python:3.11-slim-bookworm@sha256:a83ba18aef0f865b1a4a611c2cf460fe446f2795673bbb9fe43be570439e3b39
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg libgomp1 && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 1001 decoder && useradd -u 1001 -g 1001 -M -s /usr/sbin/nologin decoder
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY models/base.pt /models/base.pt
RUN python -c "import hashlib; assert hashlib.sha256(open('/models/base.pt','rb').read()).hexdigest() == 'ed3a0b6b1c0edf879ad9b11b1af5a0e6ab5db9205f891f668f8b0e6c6326e34e'"
COPY worker.py /app/worker.py
ENV PYTHONDONTWRITEBYTECODE=1 OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 NUMBA_NUM_THREADS=2
WORKDIR /app
CMD ["python", "/app/worker.py"]
