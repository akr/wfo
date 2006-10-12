class String
  def vanish!
    0.upto(self.length-1) {|i|
      self[i] = ?\0
    }
    self.replace ""
  end
end

