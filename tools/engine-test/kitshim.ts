// @kit.* 的 Node 桩：只有离线引擎回归用得到，真机上走鸿蒙自己的实现。
// 目前只覆盖 Engine 里用到的几处（md5 摘要、utf8 解码、buffer.from）。

export const cryptoFramework = {
  createMd: (_alg: string) => {
    return {
      update: (_data: unknown) => {
      },
      digest: () => new Uint8Array(0)
    };
  }
};

export const buffer = {
  from: (value: string, _encoding?: string) => Buffer.from(value, 'utf8')
};

export const util = {
  TextDecoder: {
    create: (_encoding: string) => {
      return {
        decodeToString: (bytes: Uint8Array) => Buffer.from(bytes).toString('utf8')
      };
    }
  }
};
