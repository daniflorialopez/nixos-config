{ ... }:

{
  services.keyd.keyboards.default.settings = {
    main.pause = "toggle(vf)";

    vf = {
      pause = "toggle(vf)";

      # fake thumb R
      leftalt = "r";

      # top row
      q = "x";
      w = "z";
      e = "w";
      r = "q";
      t = "m";
      y = "g";
      u = "j";
      i = "apostrophe";
      o = "dot";
      p = "slash";

      # home row
      a = "s";
      s = "c";
      d = "n";
      f = "t";
      g = "k";
      h = "comma";
      j = "a";
      k = "e";
      l = "i";
      ";" = "h";

      # bottom row
      z = "f";
      x = "p";
      c = "l";
      v = "d";
      b = "v";
      n = "minus";
      m = "u";
      "," = "o";
      "." = "y";
      "/" = "b";
    };
  };
}
